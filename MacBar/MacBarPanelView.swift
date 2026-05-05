import SwiftUI
import AppKit

/// 面板主视图 —— 磨砂玻璃背景 + 应用图标网格
struct MacBarPanelView: View {
    @ObservedObject var menuBarManager: MenuBarManager
    var onClose: () -> Void
    var onQuit: () -> Void = {}
    var onShowSettings: () -> Void = {}

    /// 控制图标悬停高亮状态
    @State private var hoveredItemId: UUID? = nil
    @State private var displayedItems: [MenuBarItem] = []

    // 网格列定义（自适应宽度）
    private let columns = [
        GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 12)
    ]

    var body: some View {
        ZStack {
            // 磨砂玻璃背景
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 0) {
                // 顶部标题栏
                headerView

                Divider()
                    .opacity(0.3)

                // 应用图标网格
                if displayedItems.isEmpty {
                    emptyStateView
                } else {
                    iconGridView
                }

                Divider()
                    .opacity(0.3)

                // 底部工具栏
                footerView
            }
        }
        .frame(width: 380)
        .onAppear {
            syncDisplayedItems()
            menuBarManager.refreshAfterPanelAppears()
        }
        .onReceive(menuBarManager.$managedItems) { items in
            DebugLog.write("MacBarPanelView received items=\(items.count)")
            displayedItems = items
        }
        .overlay(
            // 边框光晕
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - 顶部标题栏

    private var headerView: some View {
        HStack(spacing: 8) {
            // MacBar 图标
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#A78BFA"), Color(hex: "#60A5FA")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("MacBar")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            Spacer()

            // 图标数量徽章
            if !displayedItems.isEmpty {
                Text("\(displayedItems.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#A78BFA"), Color(hex: "#60A5FA")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }

            // 刷新按钮
            Button(action: {
                syncDisplayedItems()
                menuBarManager.refreshMenuBarItems(force: true)
            }) {
                if menuBarManager.isRefreshing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 图标网格

    private var iconGridView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(displayedItems) { item in
                    AppIconCell(
                        item: item,
                        isHovered: hoveredItemId == item.id,
                        onHover: { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredItemId = hovering ? item.id : nil
                            }
                        },
                        onTap: {
                            // 为了不让你误以为是闪退，我暂时去掉了立刻关闭面板的代码。
                            // 这样点击之后，面板不会马上消失，你可以确认菜单是否真的被唤起了。
                            // onClose()
                            
                            // 延迟执行，给一点缓冲时间
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                menuBarManager.activateItem(item)
                            }
                        }
                    )
                }
            }
            .padding(16)
        }
        .frame(height: iconGridHeight)
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(menuBarManager.isRefreshing ? "正在扫描菜单栏图标" : "暂无聚合的应用图标")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text(menuBarManager.isRefreshing ? "稍等一下，扫描完成后会自动显示" : "点击刷新按钮重新扫描")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
            Text(menuBarManager.lastScanSummary)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.55))
                .lineLimit(2)
        }
        .frame(height: 160)
    }

    // MARK: - 底部工具栏

    private var footerView: some View {
        HStack {
            Text("点击图标激活对应应用")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))

            Spacer()

            // 退出应用
            Button(action: {
                onQuit()
            }) {
                Image(systemName: "power")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.red.opacity(0.1))
            )

            // 打开偏好设置
            Button(action: {
                onShowSettings()
                onClose()
            }) {
                Image(systemName: "gear")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func syncDisplayedItems() {
        DebugLog.write("MacBarPanelView syncDisplayedItems count=\(menuBarManager.managedItems.count)")
        displayedItems = menuBarManager.managedItems
    }

    private var iconGridHeight: CGFloat {
        let rowCount = max(1, Int(ceil(Double(displayedItems.count) / 4.0)))
        let contentHeight = 32 + CGFloat(rowCount * 74) + CGFloat(max(0, rowCount - 1) * 12)
        return min(260, max(110, contentHeight))
    }
}

// MARK: - 单个应用图标 Cell

struct AppIconCell: View {
    let item: MenuBarItem
    var isHovered: Bool
    var onHover: (Bool) -> Void
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // 应用图标
                ZStack {
                    // 悬停背景光晕
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            isHovered
                                ? LinearGradient(
                                    colors: [Color(hex: "#A78BFA").opacity(0.25), Color(hex: "#60A5FA").opacity(0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color.clear, Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 56, height: 56)

                    // 应用图标图像
                    if let icon = item.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        // 默认占位图标
                        Image(systemName: "app.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#A78BFA"), Color(hex: "#60A5FA")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                    }
                }
                .scaleEffect(isHovered ? 1.08 : 1.0)

                // 应用名称（最多两行，截断）
                Text(item.appName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(isHovered ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 70)
            }
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
    }
}

// MARK: - 磨砂玻璃背景视图（NSVisualEffectView 封装）

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Color 扩展：支持十六进制颜色

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
