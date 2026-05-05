// @preconcurrency 抑制 C 框架导入时的并发警告（Swift 6 兼容方式）
@preconcurrency import AppKit
@preconcurrency import ApplicationServices

/// 辅助功能权限管理器
@MainActor
class PermissionManager: ObservableObject {

    /// 当前辅助功能权限状态（驱动 UI 更新）
    @Published var isAccessibilityGranted: Bool = false
    private var pollingTimer: Timer?

    init() {
        checkPermission()
    }

    /// 检查当前是否已授予辅助功能权限
    func checkPermission() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    /// 请求辅助功能权限（弹出系统对话框）
    func requestPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        isAccessibilityGranted = trusted

        if !trusted {
            // 打开系统设置中的辅助功能页面
            openAccessibilitySettings()
        }
    }

    /// 跳转到系统设置的辅助功能权限页面
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 开始轮询权限状态（用户在系统设置中授权后自动刷新）
    func startPollingPermission(callback: @escaping @Sendable () -> Void) {
        pollingTimer?.invalidate()

        if checkAndNotifyIfGranted(callback: callback) {
            return
        }

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            let granted = AXIsProcessTrusted()
            Task { @MainActor in
                guard let self else { return }
                self.isAccessibilityGranted = granted
                if granted {
                    self.pollingTimer?.invalidate()
                    self.pollingTimer = nil
                    callback()
                }
            }
        }
        pollingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @discardableResult
    func checkAndNotifyIfGranted(callback: @escaping @Sendable () -> Void) -> Bool {
        checkPermission()
        if isAccessibilityGranted {
            pollingTimer?.invalidate()
            pollingTimer = nil
            callback()
            return true
        }
        return false
    }
}
