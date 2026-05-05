import SwiftUI
import AppKit

/// MacBar 2.0 面板：一行横向聚合代理条。
struct MacBarPanelView: View {
    @ObservedObject var menuBarManager: MenuBarManager
    var onClose: () -> Void
    var onQuit: () -> Void = {}
    var onShowSettings: () -> Void = {}

    @State private var displayedItems: [MenuBarItem] = []

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 8) {
                if displayedItems.isEmpty {
                    emptyStateView
                } else {
                    HorizontalIconStripView(
                        items: displayedItems,
                        activeItemID: menuBarManager.activeItemID
                    ) { item in
                        menuBarManager.activateItem(item, onAutoClose: onClose)
                    } onExclude: { item in
                        menuBarManager.setExcluded(true, bundleID: item.bundleIdentifier)
                    }
                }

                controlsView
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .frame(width: panelWidth)
        .onAppear {
            syncDisplayedItems()
            menuBarManager.refreshAfterPanelAppears()
        }
        .onReceive(menuBarManager.$managedItems) { items in
            DebugLog.write("MacBarPanelView received items=\(items.count)")
            displayedItems = items
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.26), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private var panelWidth: CGFloat {
        let itemCount = max(1, displayedItems.count)
        let iconsWidth = CGFloat(itemCount * 32 + max(0, itemCount - 1) * 5 + 4)
        let contentWidth = iconsWidth + 8 + 100 + 16
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 900
        return min(screenWidth - 24, max(168, contentWidth))
    }

    private var controlsView: some View {
        HStack(spacing: 5) {
            Button(action: {
                syncDisplayedItems()
                menuBarManager.refreshMenuBarItems(force: true)
            }) {
                if menuBarManager.isRefreshing {
                    ProgressView()
                        .scaleEffect(0.58)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .help("刷新菜单栏图标")
            .buttonStyle(CompactIconButtonStyle())

            Button(action: onQuit) {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red.opacity(0.82))
            }
            .help("退出 MacBar")
            .buttonStyle(CompactIconButtonStyle())

            Button(action: {
                onShowSettings()
                onClose()
            }) {
                Image(systemName: "gear")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .help("打开设置")
            .buttonStyle(CompactIconButtonStyle())
        }
    }

    private var emptyStateView: some View {
        Image(systemName: menuBarManager.isRefreshing ? "arrow.triangle.2.circlepath" : "menubar.rectangle")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 34, height: 32)
    }

    private func syncDisplayedItems() {
        DebugLog.write("MacBarPanelView syncDisplayedItems count=\(menuBarManager.managedItems.count)")
        displayedItems = menuBarManager.managedItems
    }
}

struct HorizontalIconStripView: View {
    let items: [MenuBarItem]
    let activeItemID: String?
    let onTap: (MenuBarItem) -> Void
    let onExclude: (MenuBarItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 5) {
                ForEach(items) { item in
                    MenuBarProxyIconCell(
                        item: item,
                        isActive: activeItemID == item.id,
                        onTap: { onTap(item) },
                        onExclude: { onExclude(item) }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 34)
    }
}

struct MenuBarProxyIconCell: View {
    let item: MenuBarItem
    let isActive: Bool
    let onTap: () -> Void
    let onExclude: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundFill)
                    .frame(width: 30, height: 30)

                iconView
                    .frame(width: 22, height: 22)
            }
            .scaleEffect(isHovered || isActive ? 1.06 : 1.0)
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .help("\(item.appName) - \(item.aggregationState.label)")
        .contextMenu {
            Text(item.bundleIdentifier)
            Divider()
            Button("从 MacBar 排除", action: onExclude)
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = item.statusIcon ?? item.appIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#A78BFA"), Color(hex: "#60A5FA")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var backgroundFill: LinearGradient {
        if isActive {
            return LinearGradient(
                colors: [Color(hex: "#A78BFA").opacity(0.24), Color(hex: "#60A5FA").opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        if isHovered {
            return LinearGradient(
                colors: [Color.primary.opacity(0.10), Color.primary.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [Color.clear, Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct CompactIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.14) : Color.primary.opacity(0.06))
            )
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
