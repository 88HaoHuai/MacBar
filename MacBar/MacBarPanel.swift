import AppKit
import SwiftUI

/// MacBar 的浮动面板（点击菜单栏图标后展示）
/// 使用 NSPanel 实现无标题栏、磨砂玻璃风格的浮层
class MacBarPanel: NSPanel {

    private let menuBarManager: MenuBarManager
    private var hostingView: NSView?

    init(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager

        // 配置面板样式：无标题栏、支持透明度、非激活也可交互
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 面板配置
        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false

        // 点击面板外区域关闭
        self.hidesOnDeactivate = false

        setupContent()
    }

    // MARK: - 内容设置

    private func setupContent() {
        let contentView = MacBarPanelView(
            menuBarManager: menuBarManager,
            onClose: { [weak self] in
                self?.close()
            },
            onQuit: {
                (NSApp.delegate as? AppDelegate)?.quitFromUI()
            },
            onShowSettings: {
                (NSApp.delegate as? AppDelegate)?.showSettingsWindow()
            }
        )

        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = self.contentRect(forFrameRect: self.frame)
        hosting.autoresizingMask = [.width, .height]

        self.contentView = hosting
        self.hostingView = hosting
    }

    // MARK: - 显示位置计算

    /// 在菜单栏图标正下方显示面板
    func showBelow(buttonFrame: NSRect) {
        // 面板宽度
        let panelWidth: CGFloat = 380
        let panelHeight: CGFloat = 340

        // 计算居中于图标的 X 坐标
        var x = buttonFrame.midX - panelWidth / 2
        // Y 坐标：菜单栏下方，留出 4pt 间距
        let y = buttonFrame.minY - panelHeight - 4

        // 防止面板超出屏幕左边缘
        if let screen = NSScreen.main {
            let screenLeft = screen.visibleFrame.minX
            let screenRight = screen.visibleFrame.maxX
            x = max(x, screenLeft + 8)
            x = min(x, screenRight - panelWidth - 8)
        }

        let frame = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
        self.setFrame(frame, display: true)

        // 更新 SwiftUI 视图内容
        setupContent()

        self.makeKeyAndOrderFront(nil)
        self.orderFrontRegardless()
    }

    override func close() {
        orderOut(nil)
    }

    // MARK: - 鼠标点击面板外关闭

    override func mouseDown(with event: NSEvent) {
        // 让父类处理
        super.mouseDown(with: event)
    }
}
