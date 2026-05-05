import AppKit
import SwiftUI

/// 应用委托，负责菜单栏图标的创建和面板管理
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // MacBar 自身的菜单栏图标（主入口）
    private var statusItem: NSStatusItem?
    // 隐藏占位符（利用超长宽度把左侧的图标挤出屏幕）
    private var hiderItem: NSStatusItem?
    // 分隔符图标（作为用户可拖拽的边界标志，可选）
    private var separatorItem: NSStatusItem?

    // 弹出的浮动面板
    private var panel: MacBarPanel?
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

        // 菜单栏入口由 MacBarApp 中的 SwiftUI MenuBarExtra 提供。
        // 保留 AppDelegate 负责权限、设置窗口和后续 AppKit 面板能力。

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
        // 系统会在进程退出时自动清理状态栏图标，不需要手动 removeStatusItem
        permissionWarmupTimer?.invalidate()
        permissionWarmupTimer = nil
        statusItem = nil
        hiderItem = nil
        separatorItem = nil
    }

    // MARK: - 状态栏图标设置

    private func setupStatusItems() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.isVisible = true

        if let button = item.button {
            let image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "MacBar")
            image?.isTemplate = true
            button.image = image
            button.title = image == nil ? "MacBar" : " MacBar"
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "MacBar"
            button.action = #selector(statusItemClicked)
            button.target = self
            button.isEnabled = true
            NSLog("[MacBar] status item configured: image=\(image != nil), title=\(button.title)")
        } else {
            NSLog("[MacBar] status item button is nil")
        }

        hiderItem = nil
        separatorItem = nil
    }
    
    // MARK: - 临时展开以触发菜单
    
    func temporarilyUnhide(for action: @escaping () -> Void) {
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

    // MARK: - 点击菜单栏图标

    @objc private func statusItemClicked() {
        print("[MacBar] statusItemClicked START")
        // 检查权限
        guard permissionManager.isAccessibilityGranted else {
            print("[MacBar] permission NOT granted, showing permission window")
            showPermissionWindow()
            print("[MacBar] statusItemClicked END (permission flow)")
            return
        }

        if let panel = panel, panel.isVisible {
            print("[MacBar] closing panel")
            panel.close()
        } else {
            print("[MacBar] showing panel")
            showPanel()
        }
        print("[MacBar] statusItemClicked END")
    }

    // MARK: - 展示浮动面板

    private func showPanel() {
        print("[MacBar] showPanel START")
        menuBarManager.detectMenuBarItems()

        print("[MacBar] showPanel: statusItem.button=\(statusItem?.button != nil ? "OK" : "nil")")
        guard let statusItem,
              let button = statusItem.button,
              let buttonWindow = button.window else {
            print("[MacBar] showPanel: button or buttonWindow is nil, returning")
            return
        }

        print("[MacBar] showPanel: got buttonWindow")
        let buttonFrame = buttonWindow.convertToScreen(button.frame)

        if panel == nil {
            print("[MacBar] showPanel: creating new MacBarPanel")
            panel = MacBarPanel(menuBarManager: menuBarManager)
        }

        print("[MacBar] showPanel: calling showBelow")
        panel?.showBelow(buttonFrame: buttonFrame)
        print("[MacBar] showPanel END")
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

        let hosting = NSHostingController(rootView: SettingsView())
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
