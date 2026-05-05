import AppKit
import ApplicationServices

/// 描述一个被 MacBar 聚合管理的菜单栏图标
struct MenuBarItem: Identifiable {
    let id: UUID = UUID()
    /// 在 SystemUIServer 的 AXExtrasMenuBar 中对应的子元素（可设置 position / 执行 press）
    let axElement: AXUIElement
    /// 应用显示名称
    var appName: String
    /// 应用图标
    var appIcon: NSImage?
    /// 图标在菜单栏中的原始坐标（用于恢复）
    var originalPosition: CGPoint
    /// 是否当前处于隐藏状态
    var isHidden: Bool = false
    /// 关联的运行中应用（用于 fallback 激活）
    var associatedApp: NSRunningApplication?

    init(
        axElement: AXUIElement,
        appName: String,
        appIcon: NSImage?,
        originalPosition: CGPoint,
        associatedApp: NSRunningApplication? = nil
    ) {
        self.axElement = axElement
        self.appName = appName
        self.appIcon = appIcon
        self.originalPosition = originalPosition
        self.associatedApp = associatedApp
    }
}
