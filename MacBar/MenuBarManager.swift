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
    @Published var lastActionMessage: String?
    @Published var activeItemID: String?
    @Published private(set) var excludedBundleIDs: Set<String> = []

    /// 系统应用 Bundle ID 前缀（跳过这些应用的聚合）
    private let systemBundlePrefixes = ["com.apple.", "com.macbar.app"]
    private let defaults = UserDefaults.standard
    private let aggregationEnabledKey = "aggregationEnabled"
    private let autoRefreshEnabledKey = "autoRefreshEnabled"
    private let hideOriginalMenuBarItemsKey = "hideOriginalMenuBarItems"
    private let clickAutoCloseDelayKey = "clickAutoCloseDelay"
    private let excludedBundleIDsKey = "excludedBundleIDs"
    private let hiddenOriginalPositionsKey = "hiddenOriginalMenuBarPositions"
    private var lastScanDate: Date?
    private var pendingRefresh: DispatchWorkItem?
    private var emptyRetryCount = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private var hiddenItems: [String: HiddenMenuBarItem] = [:]

    var aggregationEnabled: Bool {
        defaults.object(forKey: aggregationEnabledKey) as? Bool ?? true
    }

    var autoRefreshEnabled: Bool {
        defaults.object(forKey: autoRefreshEnabledKey) as? Bool ?? true
    }

    var hideOriginalMenuBarItems: Bool {
        defaults.object(forKey: hideOriginalMenuBarItemsKey) as? Bool ?? true
    }

    var clickAutoCloseDelay: Double {
        let value = defaults.double(forKey: clickAutoCloseDelayKey)
        return value > 0 ? value : 0.8
    }

    init() {
        loadExcludedBundleIDs()
        installWorkspaceObservers()
        restorePersistedHiddenMenuBarItems(reason: "startup")
    }

    deinit {
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

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
        if !force && !autoRefreshEnabled { return }

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
        restorePersistedHiddenMenuBarItems(reason: "before scan")
        restoreHiddenMenuBarItems(reason: "before scan")

        var items: [MenuBarItem] = []
        let runningApps = NSWorkspace.shared.runningApplications
        var failures: [String] = []
        let iconSnapshot = MenuBarIconSnapshot.capture()
        logger.info("scanning menu bar items from \(runningApps.count, privacy: .public) running apps")
        DebugLog.write("detectMenuBarItems apps=\(runningApps.count)")

        guard aggregationEnabled else {
            managedItems = []
            lastScanSummary = "聚合已关闭"
            DebugLog.write(lastScanSummary)
            return
        }

        for app in runningApps {
            guard shouldManageApp(app) else { continue }

            let pid = app.processIdentifier
            let appElem = AXUIElementCreateApplication(pid)

            let (child, extrasResult, childrenResult) = firstMenuBarChild(for: appElem)
            guard let child else {
                failures.append("\(app.localizedName ?? bidForLog(app)): extras=\(extrasResult.rawValue)")
                if childrenResult != .success {
                    failures.append("\(app.localizedName ?? bidForLog(app)): children=\(childrenResult.rawValue)")
                }
                continue
            }

            let bundleID = app.bundleIdentifier ?? bidForLog(app)
            let frame = rectValue(for: child, attribute: "AXFrame" as CFString)
            let position = pointValue(for: child, attribute: kAXPositionAttribute as CFString)
            let size = sizeValue(for: child, attribute: kAXSizeAttribute as CFString)
            let title = stringValue(for: child, attribute: kAXTitleAttribute as CFString)
            let role = stringValue(for: child, attribute: kAXRoleAttribute as CFString)
            let actionable = boolValue(for: child, attribute: kAXEnabledAttribute as CFString) ?? true
            let state: AggregationState = excludedBundleIDs.contains(bundleID) ? .excluded : .proxied

            guard state != .excluded else { continue }

            let item = MenuBarItem(
                axElement: child,
                bundleIdentifier: bundleID,
                processIdentifier: pid,
                appName: app.localizedName ?? (app.bundleIdentifier ?? "未知"),
                appIcon: app.icon,
                statusIcon: iconSnapshot?.iconImage(for: frame),
                originalPosition: position,
                currentFrame: frame,
                currentSize: size,
                axTitle: title,
                axRole: role,
                isActionable: actionable,
                aggregationState: actionable ? .proxied : .unavailable,
                associatedApp: app
            )
            items.append(item)
        }

        managedItems = items
        hideManagedMenuBarItems(items)
        lastScanSummary = "扫描到 \(items.count) 个图标"
        logger.info("scan completed with \(items.count, privacy: .public) item(s): \(items.map(\.appName).joined(separator: ", "), privacy: .public)")
        DebugLog.write("scan completed count=\(items.count) names=\(items.map(\.appName).joined(separator: ",")) failures=\(failures.joined(separator: " | "))")
    }

    // MARK: - 激活

    /// 触发对应图标的菜单
    func activateItem(_ item: MenuBarItem, onAutoClose: @escaping () -> Void = {}) {
        activeItemID = item.id
        lastActionMessage = "正在打开 \(item.appName)"
        let wasHidden = restoreHiddenMenuBarItem(item, reason: "before press")

        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.temporarilyRevealMenuBarItems {
                self.performPress(item: item, shouldRehideAfterPress: wasHidden, onAutoClose: onAutoClose)
            }
        } else {
            performPress(item: item, shouldRehideAfterPress: wasHidden, onAutoClose: onAutoClose)
        }
    }

    private func performPress(item: MenuBarItem, shouldRehideAfterPress: Bool, onAutoClose: @escaping () -> Void) {
        // 执行点击动作（AXPressAction）
        let pressResult = AXUIElementPerformAction(item.axElement, kAXPressAction as CFString)
        print("[MacBar] AXPress: \(pressResult.rawValue) (\(item.appName))")
        DebugLog.write("AXPress app=\(item.appName) result=\(pressResult.rawValue)")

        // 如果 Press 失败，作为降级方案直接激活该应用
        if pressResult != .success {
            item.associatedApp?.activate(options: .activateIgnoringOtherApps)
            lastActionMessage = "\(item.appName) 无法直接打开菜单，已尝试激活应用"
        } else {
            lastActionMessage = "已打开 \(item.appName)"
            let delay = clickAutoCloseDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                onAutoClose()
            }
        }

        if shouldRehideAfterPress {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.hideMenuBarItem(item, reason: "after press")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            if self.activeItemID == item.id {
                self.activeItemID = nil
            }
        }
    }

    // MARK: - 配置

    func isExcluded(_ bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID)
    }

    func setExcluded(_ excluded: Bool, bundleID: String) {
        restoreHiddenMenuBarItems(bundleID: bundleID, reason: excluded ? "exclude" : "restore exclusion")

        if excluded {
            excludedBundleIDs.insert(bundleID)
        } else {
            excludedBundleIDs.remove(bundleID)
        }
        persistExcludedBundleIDs()
        refreshMenuBarItems(force: true)
    }

    func reloadConfigurationAndRefresh() {
        loadExcludedBundleIDs()
        if !hideOriginalMenuBarItems {
            restoreHiddenMenuBarItems(reason: "hide disabled")
        }
        refreshMenuBarItems(force: true)
    }

    func restoreHiddenMenuBarItems(reason: String = "manual") {
        restoreHiddenMenuBarItems(bundleID: nil, reason: reason)
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

    private func loadExcludedBundleIDs() {
        let raw = defaults.string(forKey: excludedBundleIDsKey) ?? ""
        excludedBundleIDs = Set(
            raw
                .split(separator: ",")
                .map { String($0) }
                .filter { !$0.isEmpty }
        )
    }

    private func persistExcludedBundleIDs() {
        defaults.set(excludedBundleIDs.sorted().joined(separator: ","), forKey: excludedBundleIDsKey)
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMenuBarItems(force: false)
            }
        }
        let terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMenuBarItems(force: false)
            }
        }
        workspaceObservers = [launchObserver, terminateObserver]
    }

    // MARK: - 原菜单栏隐藏（尽力而为）

    private func hideManagedMenuBarItems(_ items: [MenuBarItem]) {
        guard hideOriginalMenuBarItems else {
            restoreHiddenMenuBarItems(reason: "hide disabled")
            return
        }

        for (index, item) in items.enumerated() {
            hideMenuBarItem(item, index: index, reason: "after scan")
        }
    }

    @discardableResult
    private func hideMenuBarItem(_ item: MenuBarItem, index: Int = 0, reason: String) -> Bool {
        guard hideOriginalMenuBarItems else { return false }
        guard hiddenItems[item.id] == nil else { return true }
        guard item.originalPosition != .zero || item.currentFrame != .zero else {
            DebugLog.write("hide skipped app=\(item.appName) reason=\(reason) missing position")
            return false
        }

        let originalPosition = item.originalPosition == .zero
            ? CGPoint(x: item.currentFrame.minX, y: item.currentFrame.minY)
            : item.originalPosition
        let hiddenPosition = CGPoint(
            x: -10000 - CGFloat(index * 48),
            y: originalPosition.y
        )
        hiddenItems[item.id] = HiddenMenuBarItem(
            bundleIdentifier: item.bundleIdentifier,
            processIdentifier: item.processIdentifier,
            element: item.axElement,
            originalPosition: originalPosition
        )
        persistHiddenMenuBarItems()

        let result = setPosition(hiddenPosition, for: item.axElement)

        if result == .success {
            DebugLog.write("hide success app=\(item.appName) id=\(item.id) reason=\(reason)")
            return true
        }

        DebugLog.write("hide attempted app=\(item.appName) id=\(item.id) result=\(result.rawValue) reason=\(reason)")
        return true
    }

    @discardableResult
    private func restoreHiddenMenuBarItem(_ item: MenuBarItem, reason: String) -> Bool {
        guard let hiddenItem = hiddenItems.removeValue(forKey: item.id) else {
            return false
        }

        let result = setPosition(hiddenItem.originalPosition, for: hiddenItem.element)
        persistHiddenMenuBarItems()
        DebugLog.write("restore hidden item app=\(item.appName) id=\(item.id) result=\(result.rawValue) reason=\(reason)")
        return true
    }

    private func restoreHiddenMenuBarItems(bundleID: String? = nil, reason: String) {
        let matchingKeys = hiddenItems
            .filter { bundleID == nil || $0.value.bundleIdentifier == bundleID }
            .map(\.key)

        for key in matchingKeys {
            guard let hiddenItem = hiddenItems.removeValue(forKey: key) else { continue }
            let result = setPosition(hiddenItem.originalPosition, for: hiddenItem.element)
            DebugLog.write("restore hidden item id=\(key) result=\(result.rawValue) reason=\(reason)")
        }
        persistHiddenMenuBarItems()
    }

    private func persistHiddenMenuBarItems() {
        let records = hiddenItems.map { key, item in
            HiddenMenuBarItemRecord(
                id: key,
                bundleIdentifier: item.bundleIdentifier,
                processIdentifier: item.processIdentifier,
                x: item.originalPosition.x,
                y: item.originalPosition.y
            )
        }

        if records.isEmpty {
            defaults.removeObject(forKey: hiddenOriginalPositionsKey)
            return
        }

        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: hiddenOriginalPositionsKey)
        }
    }

    private func restorePersistedHiddenMenuBarItems(bundleID: String? = nil, reason: String) {
        guard let data = defaults.data(forKey: hiddenOriginalPositionsKey),
              let records = try? JSONDecoder().decode([HiddenMenuBarItemRecord].self, from: data),
              !records.isEmpty else {
            return
        }

        var remainingRecords: [HiddenMenuBarItemRecord] = []

        for record in records {
            guard bundleID == nil || record.bundleIdentifier == bundleID else {
                remainingRecords.append(record)
                continue
            }

            guard let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == record.bundleIdentifier &&
                $0.processIdentifier == record.processIdentifier
            }) else {
                continue
            }

            let appElem = AXUIElementCreateApplication(app.processIdentifier)
            let (child, _, _) = firstMenuBarChild(for: appElem)
            guard let child else { continue }

            let originalPosition = CGPoint(x: record.x, y: record.y)
            let result = setPosition(originalPosition, for: child)
            DebugLog.write("restore persisted hidden item id=\(record.id) result=\(result.rawValue) reason=\(reason)")
        }

        if remainingRecords.isEmpty {
            defaults.removeObject(forKey: hiddenOriginalPositionsKey)
        } else if let remainingData = try? JSONEncoder().encode(remainingRecords) {
            defaults.set(remainingData, forKey: hiddenOriginalPositionsKey)
        }
    }

    private func setPosition(_ position: CGPoint, for element: AXUIElement) -> AXError {
        var point = position
        guard let axValue = AXValueCreate(.cgPoint, &point) else {
            return .failure
        }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axValue)
    }

    private func firstMenuBarChild(for appElement: AXUIElement) -> (AXUIElement?, AXError, AXError) {
        var extrasRef: CFTypeRef?
        let extrasResult = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasRef)
        guard extrasResult == .success, let extras = extrasRef else {
            return (nil, extrasResult, .failure)
        }

        let extrasElem = extras as! AXUIElement
        var childrenRef: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(extrasElem, kAXChildrenAttribute as CFString, &childrenRef)
        guard childrenResult == .success,
              let children = childrenRef as? [AXUIElement],
              let child = children.first else {
            return (nil, extrasResult, childrenResult)
        }

        return (child, extrasResult, childrenResult)
    }

    private func stringValue(for element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func boolValue(for element: AXUIElement, attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private func pointValue(for element: AXUIElement, attribute: CFString) -> CGPoint {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return .zero
        }

        var point = CGPoint.zero
        AXValueGetValue(axValue as! AXValue, .cgPoint, &point)
        return point
    }

    private func sizeValue(for element: AXUIElement, attribute: CFString) -> CGSize {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return .zero
        }

        var size = CGSize.zero
        AXValueGetValue(axValue as! AXValue, .cgSize, &size)
        return size
    }

    private func rectValue(for element: AXUIElement, attribute: CFString) -> CGRect {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return .zero
        }

        var rect = CGRect.zero
        AXValueGetValue(axValue as! AXValue, .cgRect, &rect)
        return rect
    }
}

private struct MenuBarIconSnapshot {
    private let image: CGImage
    private let scale: CGFloat

    static func capture() -> MenuBarIconSnapshot? {
        guard CGPreflightScreenCaptureAccess() else {
            DebugLog.write("status icon capture skipped: screen recording permission is not granted")
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macbar-menubar-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "png", url.path]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            DebugLog.write("status icon capture failed to run: \(error.localizedDescription)")
            return nil
        }

        guard process.terminationStatus == 0,
              let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              nsImage.size.width > 0 else {
            DebugLog.write("status icon capture unavailable status=\(process.terminationStatus)")
            return nil
        }

        let scale = CGFloat(cgImage.width) / nsImage.size.width
        return MenuBarIconSnapshot(image: cgImage, scale: scale)
    }

    func iconImage(for frame: CGRect) -> NSImage? {
        guard frame.width >= 10,
              frame.height >= 10,
              frame.minX >= 0,
              frame.minY >= 0,
              frame.minY <= 36 else {
            return nil
        }

        let targetWidth = min(frame.width, 26)
        let targetHeight = min(frame.height, 24)
        let pointRect = CGRect(
            x: frame.midX - targetWidth / 2,
            y: frame.midY - targetHeight / 2,
            width: targetWidth,
            height: targetHeight
        )

        let pixelBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let pixelRect = CGRect(
            x: floor(pointRect.minX * scale),
            y: floor(pointRect.minY * scale),
            width: ceil(pointRect.width * scale),
            height: ceil(pointRect.height * scale)
        )
        .intersection(pixelBounds)
        .integral

        guard pixelRect.width > 0,
              pixelRect.height > 0,
              let cropped = image.cropping(to: pixelRect) else {
            return nil
        }

        return NSImage(
            cgImage: cropped,
            size: CGSize(width: pixelRect.width / scale, height: pixelRect.height / scale)
        )
    }
}

private struct HiddenMenuBarItem {
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let element: AXUIElement
    let originalPosition: CGPoint
}

private struct HiddenMenuBarItemRecord: Codable {
    let id: String
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let x: CGFloat
    let y: CGFloat
}
