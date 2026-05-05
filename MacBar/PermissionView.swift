import AppKit
import SwiftUI

/// 权限引导界面：引导用户在系统设置中授权辅助功能
struct PermissionView: View {
    @ObservedObject var permissionManager: PermissionManager
    var onRelaunch: (() -> Void)? = nil
    var onGranted: () -> Void

    @State private var isPolling = false
    @State private var pulseAnimation = false
    @State private var lastCheckText = "正在检查当前运行的 MacBar..."

    var body: some View {
        VStack(spacing: 28) {
            // 顶部图标
            ZStack {
                // 渐变光晕背景
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "#A78BFA").opacity(0.3),
                                Color(hex: "#60A5FA").opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseAnimation ? 1.15 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#A78BFA"), Color(hex: "#60A5FA")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .onAppear { pulseAnimation = true }

            // 标题和说明文字
            VStack(spacing: 10) {
                Text("需要辅助功能权限")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("MacBar 需要辅助功能权限来\n管理其他应用的菜单栏图标")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // 步骤说明
            VStack(spacing: 12) {
                PermissionStep(number: "1", text: "点击下方按钮打开系统设置")
                PermissionStep(number: "2", text: "在「隐私与安全性 → 辅助功能」中找到 MacBar")
                PermissionStep(number: "3", text: "打开 MacBar 旁边的开关")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )

            // 按钮组
            VStack(spacing: 10) {
                // 主要操作按钮
                Button(action: {
                    permissionManager.requestPermission()
                    startPolling()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "gear")
                            .font(.system(size: 14, weight: .medium))
                        Text("打开系统设置")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#A78BFA"), Color(hex: "#60A5FA")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    )
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Button(action: {
                        startPolling()
                    }) {
                        Text("我已授权，重新检查")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }) {
                        Text("显示当前版本")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // 等待状态提示
                if isPolling {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("等待授权中...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                VStack(spacing: 8) {
                    Text(lastCheckText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                    if let onRelaunch {
                        Button(action: onRelaunch) {
                            Text("授权后仍卡住？重启 MacBar")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.primary.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(32)
        .frame(width: 380)
        .onAppear {
            startPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            startPolling()
        }
    }

    private func startPolling() {
        permissionManager.checkPermission()
        lastCheckText = permissionManager.isAccessibilityGranted
            ? "已检测到授权，正在刷新..."
            : "未检测到授权：\(Bundle.main.bundlePath)"

        if permissionManager.isAccessibilityGranted {
            isPolling = false
            onGranted()
            return
        }

        isPolling = true
        permissionManager.startPollingPermission {
            Task { @MainActor in
                isPolling = false
                lastCheckText = "已检测到授权，正在刷新..."
                onGranted()
            }
        }
    }
}

/// 步骤说明条目
struct PermissionStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            // 序号圆圈
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#A78BFA"), Color(hex: "#60A5FA")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}
