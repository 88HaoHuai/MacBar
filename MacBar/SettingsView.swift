import SwiftUI

/// 偏好设置视图（通过菜单栏面板底部齿轮图标打开）
struct SettingsView: View {
    @AppStorage("hideSystemApps") private var hideSystemApps: Bool = true
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("showAppNames") private var showAppNames: Bool = true

    var body: some View {
        Form {
            Section("图标管理") {
                Toggle("隐藏系统应用图标（推荐）", isOn: $hideSystemApps)
                Toggle("在面板中显示应用名称", isOn: $showAppNames)
            }

            Section("系统") {
                // 开机自启开关（占位，后续接入 SMAppService）
                Toggle("登录时自动启动", isOn: $launchAtLogin)
            }

            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 280)
        .navigationTitle("MacBar 偏好设置")
    }

    // MARK: - 开机自启（占位实现）
    private func setLaunchAtLogin(_ enabled: Bool) { }
}
