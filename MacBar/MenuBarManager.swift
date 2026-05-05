@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import OSLog

enum DebugLog {
    private static let logURL = URL(fileURLWithPath: "/tmp/macbar-debug.log")

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }
}

/// 菜单栏图标管理核心类
@MainActor
class MenuBarManager: ObservableObject {
    private let logger = Logger(subsystem: "com.macbar.app", category: "MenuBarManager")

    /// 当前被聚合管理的图标列表
    @Published var managedItems: [MenuBarItem] = []
    @Published var isRefreshing: Bool = false
    @Published var lastScanSummary: String = "尚未扫描"

    /// 系统应用 Bundle ID 前缀（跳过这些应用的聚合）
    private let systemBundlePrefixes = ["com.apple.", "com.macbar.app"]
    private var lastScanDate: Date?
    private var pendingRefresh: DispatchWorkItem?
    private var emptyRetryCount = 0

    // MARK: - 扫描图标

    func warmUpMenuBarItems() {
        DebugLog.write("warmUpMenuBarItems")
        emptyRetryCount = 0
        refreshMenuBarItems(force: true)
    }

    /// 面板出现后刷新：先让面板显示出来，再扫描，避免点击菜单栏图标时被 AX 查询卡住。
    func refreshAfterPanelAppears() {
        DebugLog.write("refreshAfterPanelAppears")
        refreshMenuBarItems(force: true)
    }

    /// 用户点击刷新按钮时强制刷新；自动刷新时会短时间去重。
    func refreshMenuBarItems(force: Bool = false) {
        DebugLog.write("refreshMenuBarItems force=\(force) isRefreshing=\(isRefreshing) count=\(managedItems.count)")
        if isRefreshing { return }

        if !force,
           !managedItems.isEmpty,
           let lastScanDate,
           Date().timeIntervalSince(lastScanDate) < 8 {
            return
        }

        pendingRefresh?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.performRefresh()
        }
        pendingRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func performRefresh() {
        guard !isRefreshing else { return }
        DebugLog.write("performRefresh begin")
        isRefreshing = true
        detectMenuBarItems()
        lastScanDate = Date()
        isRefreshing = false

        if managedItems.isEmpty && emptyRetryCount < 4 {
            emptyRetryCount += 1
            logger.info("menu bar scan returned empty, retry \(self.emptyRetryCount, privacy: .public)")
            lastScanSummary = "扫描为空，正在重试 \(emptyRetryCount)/4"
            DebugLog.write(lastScanSummary)
            pendingRefresh?.cancel()
            let delay = 0.6 * Double(emptyRetryCount)
            let workItem = DispatchWorkItem { [weak self] in
                self?.performRefresh()
            }
            pendingRefresh = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        } else if !managedItems.isEmpty {
            emptyRetryCount = 0
        }
    }

    /// 扫描所有第三方应用的菜单栏图标
    func detectMenuBarItems() {
        var items: [MenuBarItem] = []
        let runningApps = NSWorkspace.shared.runningApplications
        var failures: [String] = []
        logger.info("scanning menu bar items from \(runningApps.count, privacy: .public) running apps")
        DebugLog.write("detectMenuBarItems apps=\(runningApps.count)")

        for app in runningApps {
            guard shouldManageApp(app) else { continue }

            let pid = app.processIdentifier
            let appElem = AXUIElementCreateApplication(pid)

            var extrasRef: CFTypeRef?
            let extrasResult = AXUIElementCopyAttributeValue(appElem, "AXExtrasMenuBar" as CFString, &extrasRef)
            guard extrasResult == .success, let extras = extrasRef else {
                failures.append("\(app.localizedName ?? bidForLog(app)): extras=\(extrasResult.rawValue)")
                continue
            }

            let extrasElem = extras as! AXUIElement

            var childrenRef: CFTypeRef?
            let childrenResult = AXUIElementCopyAttributeValue(extrasElem, kAXChildrenAttribute as CFString, &childrenRef)
            guard childrenResult == .success,
                  let children = childrenRef as? [AXUIElement],
                  let child = children.first else {
                failures.append("\(app.localizedName ?? bidForLog(app)): children=\(childrenResult.rawValue)")
                continue
            }

            // 只需要记录，不需要管坐标（UI 隐藏由 AppDelegate 的 Spacer 占位符完成）
            let item = MenuBarItem(
                axElement: child,
                appName: app.localizedName ?? (app.bundleIdentifier ?? "未知"),
                appIcon: app.icon,
                originalPosition: .zero,
                associatedApp: app
            )
            items.append(item)
        }

        managedItems = items
        lastScanSummary = "扫描到 \(items.count) 个图标"
        logger.info("scan completed with \(items.count, privacy: .public) item(s): \(items.map(\.appName).joined(separator: ", "), privacy: .public)")
        DebugLog.write("scan completed count=\(items.count) names=\(items.map(\.appName).joined(separator: ",")) failures=\(failures.joined(separator: " | "))")
    }

    // MARK: - 激活

    /// 触发对应图标的菜单
    func activateItem(_ item: MenuBarItem) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.temporarilyUnhide {
                self.performPress(item: item)
            }
        } else {
            performPress(item: item)
        }
    }

    private func performPress(item: MenuBarItem) {
        // 执行点击动作（AXPressAction）
        let pressResult = AXUIElementPerformAction(item.axElement, kAXPressAction as CFString)
        print("[MacBar] AXPress: \(pressResult.rawValue) (\(item.appName))")

        // 如果 Press 失败，作为降级方案直接激活该应用
        if pressResult != .success {
            item.associatedApp?.activate(options: .activateIgnoringOtherApps)
        }
    }

    // MARK: - 过滤

    private func shouldManageApp(_ app: NSRunningApplication) -> Bool {
        if let bid = app.bundleIdentifier {
            for prefix in systemBundlePrefixes {
                if bid.hasPrefix(prefix) { return false }
            }
        } else {
            return false
        }
        return true
    }

    private func bidForLog(_ app: NSRunningApplication) -> String {
        app.bundleIdentifier ?? "unknown"
    }
}
