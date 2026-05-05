import AppKit
import ApplicationServices

/// 描述一个被 MacBar 聚合管理的菜单栏图标
struct MenuBarItem: Identifiable {
    /// 稳定身份：优先使用 bundle id，补充 pid / title / frame，避免每次扫描都完全变成新对象。
    let id: String
    let bundleIdentifier: String
    let processIdentifier: pid_t
    /// 在 SystemUIServer 的 AXExtrasMenuBar 中对应的子元素（可设置 position / 执行 press）
    let axElement: AXUIElement
    /// 应用显示名称
    var appName: String
    /// 应用图标
    var appIcon: NSImage?
    /// 从当前菜单栏截图裁剪出的真实状态栏图标；不可用时回退到 appIcon。
    var statusIcon: NSImage?
    /// 图标在菜单栏中的原始坐标（用于恢复）
    var originalPosition: CGPoint
    /// 当前 AX 读取到的 frame / size，用于诊断和后续隐藏策略。
    var currentFrame: CGRect
    var currentSize: CGSize
    var axTitle: String?
    var axRole: String?
    var isActionable: Bool
    var aggregationState: AggregationState
    /// 是否当前处于隐藏状态
    var isHidden: Bool = false
    /// 关联的运行中应用（用于 fallback 激活）
    var associatedApp: NSRunningApplication?

    init(
        axElement: AXUIElement,
        bundleIdentifier: String,
        processIdentifier: pid_t,
        appName: String,
        appIcon: NSImage?,
        statusIcon: NSImage? = nil,
        originalPosition: CGPoint,
        currentFrame: CGRect = .zero,
        currentSize: CGSize = .zero,
        axTitle: String? = nil,
        axRole: String? = nil,
        isActionable: Bool = true,
        aggregationState: AggregationState = .proxied,
        associatedApp: NSRunningApplication? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.axElement = axElement
        self.id = MenuBarItem.makeStableID(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            title: axTitle,
            frame: currentFrame
        )
        self.appName = appName
        self.appIcon = appIcon
        self.statusIcon = statusIcon
        self.originalPosition = originalPosition
        self.currentFrame = currentFrame
        self.currentSize = currentSize
        self.axTitle = axTitle
        self.axRole = axRole
        self.isActionable = isActionable
        self.aggregationState = aggregationState
        self.associatedApp = associatedApp
    }

    static func makeStableID(
        bundleIdentifier: String,
        processIdentifier: pid_t,
        title: String?,
        frame: CGRect
    ) -> String {
        let titlePart = (title?.isEmpty == false ? title! : "untitled")
            .replacingOccurrences(of: " ", with: "-")
        let framePart = "\(Int(frame.origin.x))x\(Int(frame.origin.y))"
        return "\(bundleIdentifier)::\(processIdentifier)::\(titlePart)::\(framePart)"
    }
}

enum AggregationState: String {
    case proxied
    case excluded
    case unavailable

    var label: String {
        switch self {
        case .proxied:
            return "已聚合代理"
        case .excluded:
            return "已排除"
        case .unavailable:
            return "可显示但无法隐藏"
        }
    }
}
