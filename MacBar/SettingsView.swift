import SwiftUI

/// 偏好设置视图（通过菜单栏面板底部齿轮图标打开）
struct SettingsView: View {
    @ObservedObject var menuBarManager: MenuBarManager

    @AppStorage("aggregationEnabled") private var aggregationEnabled: Bool = true
    @AppStorage("autoRefreshEnabled") private var autoRefreshEnabled: Bool = true
    @AppStorage("hideOriginalMenuBarItems") private var hideOriginalMenuBarItems: Bool = true
    @AppStorage("clickAutoCloseDelay") private var clickAutoCloseDelay: Double = 0.8
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false

    var body: some View {
        Form {
            Section("MacBar 2.0 聚合代理") {
                Toggle("启用一行聚合代理", isOn: $aggregationEnabled)
                Toggle("运行中应用变化时自动刷新", isOn: $autoRefreshEnabled)
                Toggle("聚合后尝试隐藏原菜单栏图标", isOn: $hideOriginalMenuBarItems)
            }

            Section("点击行为") {
                HStack {
                    Text("点击后自动收起")
                    Slider(value: $clickAutoCloseDelay, in: 0.3...3.0, step: 0.1)
                    Text("\(clickAutoCloseDelay, specifier: "%.1f") 秒")
                        .foregroundColor(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }

            Section("排除列表") {
                if menuBarManager.excludedBundleIDs.isEmpty {
                    Text("暂无排除的应用")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(menuBarManager.excludedBundleIDs.sorted(), id: \.self) { bundleID in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName(for: bundleID))
                                Text(bundleID)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("恢复") {
                                menuBarManager.setExcluded(false, bundleID: bundleID)
                            }
                        }
                    }
                }
            }

            Section("当前扫描到的图标") {
                if menuBarManager.managedItems.isEmpty {
                    Text("打开 MacBar 面板或点击刷新后会显示当前可聚合项目")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(menuBarManager.managedItems) { item in
                        HStack {
                            if let icon = item.appIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.appName)
                                Text(item.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("排除") {
                                menuBarManager.setExcluded(true, bundleID: item.bundleIdentifier)
                            }
                        }
                    }
                }
            }

            Section("系统") {
                // 开机自启开关（占位，后续接入 SMAppService）
                Toggle("登录时自动启动", isOn: $launchAtLogin)
            }

            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0")
                        .foregroundColor(.secondary)
                }
                Text("MacBar 使用辅助功能 API 代理真实菜单栏项，无法把其他 App 的 NSStatusItem 真实搬进自己的视图层级。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
        .navigationTitle("MacBar 偏好设置")
        .onChange(of: aggregationEnabled) { _ in
            menuBarManager.reloadConfigurationAndRefresh()
        }
        .onChange(of: autoRefreshEnabled) { _ in
            menuBarManager.reloadConfigurationAndRefresh()
        }
        .onChange(of: hideOriginalMenuBarItems) { _ in
            menuBarManager.reloadConfigurationAndRefresh()
        }
    }

    private func displayName(for bundleID: String) -> String {
        menuBarManager.managedItems.first { $0.bundleIdentifier == bundleID }?.appName ?? bundleID
    }
}
