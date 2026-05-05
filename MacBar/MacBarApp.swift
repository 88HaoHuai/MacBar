import AppKit
import SwiftUI

@main
struct MacBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MacBarMenuBarExtraContent(
                permissionManager: appDelegate.permissionManager,
                menuBarManager: appDelegate.menuBarManager,
                onRelaunch: appDelegate.relaunchFromUI,
                onQuit: appDelegate.quitFromUI,
                onShowSettings: appDelegate.showSettingsWindow
            )
        } label: {
            Label("MacBar", systemImage: "square.grid.2x2.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

private struct MacBarMenuBarExtraContent: View {
    @ObservedObject var permissionManager: PermissionManager
    @ObservedObject var menuBarManager: MenuBarManager
    let onRelaunch: () -> Void
    let onQuit: () -> Void
    let onShowSettings: () -> Void

    var body: some View {
        Group {
            if permissionManager.isAccessibilityGranted {
                MacBarPanelView(
                    menuBarManager: menuBarManager,
                    onClose: { },
                    onQuit: onQuit,
                    onShowSettings: onShowSettings
                )
            } else {
                PermissionView(
                    permissionManager: permissionManager,
                    onRelaunch: onRelaunch
                ) {
                    menuBarManager.warmUpMenuBarItems()
                }
            }
        }
        .onAppear {
            permissionManager.checkPermission()
            if permissionManager.isAccessibilityGranted {
                menuBarManager.warmUpMenuBarItems()
            }
        }
    }
}
