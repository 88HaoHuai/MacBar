import AppKit
import SwiftUI

/// 应用委托，负责菜单栏应用生命周期、权限窗口和 AppKit 桥接
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // 隐藏占位符：2.0 首版保留为可降级桥接点，默认不强制挤压菜单栏布局。
    private var hiderItem: NSStatusItem?

    // 核心管理器
    let menuBarManager = MenuBarManager()
    // 权限管理器
    let permissionManager = PermissionManager()
    // 权限引导窗口
    private var permissionWindow: NSWindow?
    // 偏好设置窗口
    private var settingsWindow: NSWindow?
    // 纯菜单栏应用没有常规主窗口，需要显式声明为常驻任务，避免 AppKit 自动终止。
    private var residentActivity: NSObjectProtocol?
    private var allowsTermination = false
    private var permissionWarmupTimer: Timer?
    private var permissionWarmupAttempts = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("MacBar runs as a resident menu bar app.")
        residentActivity = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "MacBar stays resident in the menu bar."
        )

        // 隐藏 WindowGroup 产生的占位窗口
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title.isEmpty && window.frame.size.width <= 1 {
                window.orderOut(nil)
            }
        }

        startPermissionWarmupPolling()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        allowsTermination ? .terminateNow : .terminateCancel
    }

    @objc func quitFromUI() {
        NSLog("[MacBar] quit requested")
        allowsTermination = true
        NSApp.terminate(nil)
    }

    @objc func relaunchFromUI() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "sleep 0.35; /usr/bin/open -n \"\(bundlePath.replacingOccurrences(of: "\"", with: "\\\""))\""
        ]

        do {
            NSLog("[MacBar] relaunch requested for \(bundlePath)")
            try task.run()
            allowsTermination = true
            NSApp.terminate(nil)
        } catch {
            NSLog("[MacBar] relaunch failed: \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarManager.restoreHiddenMenuBarItems(reason: "app terminate")
        permissionWarmupTimer?.invalidate()
        permissionWarmupTimer = nil
        hiderItem = nil
    }
    
    // MARK: - 临时展开以触发菜单
    
    func temporarilyRevealMenuBarItems(for action: @escaping () -> Void) {
        guard let hiderItem else {
            action()
            return
        }

        let originalLength = hiderItem.length
        hiderItem.length = 0
        
        // 给系统一点时间重新排列菜单栏布局，否则可能找不到元素位置
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            action()
            
            // 延时恢复隐藏（留出足够的时间让用户与弹出的菜单交互）
            // 注意：更好的方案是监听菜单的关闭，这里暂时用延时作为保底方案
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                hiderItem.length = originalLength
            }
        }
    }

    // MARK: - 权限相关

    private func startPermissionWarmupPolling() {
        DebugLog.write("startPermissionWarmupPolling")
        permissionWarmupTimer?.invalidate()
        permissionWarmupAttempts = 0

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.permissionWarmupAttempts += 1
                self.permissionManager.checkPermission()
                DebugLog.write("permission warmup attempt=\(self.permissionWarmupAttempts) granted=\(self.permissionManager.isAccessibilityGranted) items=\(self.menuBarManager.managedItems.count)")

                if self.permissionManager.isAccessibilityGranted {
                    self.menuBarManager.warmUpMenuBarItems()
                    if !self.menuBarManager.managedItems.isEmpty || self.permissionWarmupAttempts >= 20 {
                        self.stopPermissionWarmupPolling()
                    }
                } else if self.permissionWarmupAttempts >= 20 {
                    self.stopPermissionWarmupPolling()
                }
            }
        }

        permissionWarmupTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPermissionWarmupPolling() {
        permissionWarmupTimer?.invalidate()
        permissionWarmupTimer = nil
    }

    /// 显示偏好设置窗口（替代 SwiftUI Settings 场景）
    @objc func showSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(menuBarManager: menuBarManager))
        let window = NSWindow(contentViewController: hosting)
        window.title = "MacBar 偏好设置"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    private func showPermissionWindow() {
        print("[MacBar] showPermissionWindow START")
        if let win = permissionWindow {
            print("[MacBar] showPermissionWindow: reusing existing window")
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        print("[MacBar] showPermissionWindow: creating new window")
        let permView = PermissionView(
            permissionManager: permissionManager,
            onRelaunch: { [weak self] in
                self?.relaunchFromUI()
            }
        ) {
            self.menuBarManager.warmUpMenuBarItems()
            self.permissionWindow?.close()
            self.permissionWindow = nil
        }
        let hosting = NSHostingController(rootView: permView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "MacBar — 需要辅助功能权限"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        permissionWindow = window
        print("[MacBar] showPermissionWindow END")
    }
}
