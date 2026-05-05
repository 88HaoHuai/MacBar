# MacBar

MacBar 是一个 macOS 菜单栏图标聚合工具。它常驻在系统菜单栏中，将其他第三方菜单栏应用的图标扫描出来，集中展示在 MacBar 面板里，减少菜单栏拥挤。

## 功能

- 常驻 macOS 菜单栏，点击 MacBar 图标打开聚合面板。
- 自动扫描第三方菜单栏图标，并显示应用图标和名称。
- 点击面板中的应用图标，可尝试激活对应菜单栏应用。
- 支持刷新当前菜单栏图标列表。
- 内置辅助功能权限引导页，授权后会自动重新检查权限。
- 提供偏好设置入口，目前包含图标显示、系统应用过滤、登录启动等选项占位。
- 纯菜单栏应用模式运行，不显示 Dock 图标。

## 系统要求

- macOS 13.0 或更高版本。
- Xcode 命令行工具或完整 Xcode。
- 可用的 Apple Development 签名证书。
- 需要授予辅助功能权限，否则无法读取和操作其他应用的菜单栏元素。

## 项目结构

```text
MacBar/
├── MacBar.xcodeproj/       # Xcode 工程
├── MacBar/                 # Swift 源码
│   ├── MacBarApp.swift     # 应用入口和 MenuBarExtra
│   ├── AppDelegate.swift   # 应用生命周期、权限轮询、设置窗口
│   ├── MenuBarManager.swift # 菜单栏图标扫描和激活逻辑
│   ├── MacBarPanelView.swift # 菜单栏面板 UI
│   ├── PermissionManager.swift
│   └── PermissionView.swift
├── script/
│   └── build_and_run.sh    # 构建、签名校验、运行脚本
└── README.md
```

## 部署和运行

### 1. 克隆项目

```bash
git clone https://github.com/88HaoHuai/MacBar.git
cd MacBar
```

### 2. 配置签名

打开 `MacBar.xcodeproj`，在 Xcode 中确认以下配置：

- `Signing & Capabilities` 使用你的 Apple Development 证书。
- `Bundle Identifier` 保持唯一，例如 `com.macbar.app` 或改成你自己的标识。
- `MacBar.entitlements` 中不要启用 App Sandbox。辅助功能跨进程访问需要关闭沙盒。

如果你直接使用命令行构建，也需要确保工程中的 `DEVELOPMENT_TEAM` 和签名证书配置可用。

### 3. 构建并运行

推荐使用项目脚本：

```bash
./script/build_and_run.sh --verify
```

脚本会执行：

- 结束当前正在运行的 MacBar 进程。
- 使用 `xcodebuild` 构建 Debug 版本。
- 将产物复制到 `build/MacBar.app`。
- 校验代码签名。
- 启动新的 MacBar。
- 检查进程是否成功启动。

也可以只构建并运行：

```bash
./script/build_and_run.sh
```

查看运行日志：

```bash
./script/build_and_run.sh --logs
```

## 辅助功能授权

首次运行时，MacBar 会提示需要辅助功能权限。请按下面步骤授权：

1. 点击 MacBar 面板中的“打开系统设置”。
2. 进入“隐私与安全性” -> “辅助功能”。
3. 找到 `MacBar`，打开右侧开关。
4. 回到 MacBar，等待自动检测，或点击“我已授权，重新检查”。
5. 如果仍然没有生效，点击“授权后仍卡住？重启 MacBar”。

注意：如果重新签名、移动 app 路径，或重新构建后替换了 `build/MacBar.app`，macOS 可能会把它视为新的应用。遇到权限异常时，请在辅助功能列表里重新开关一次 MacBar。

## 常见问题

### 菜单栏里看不到 MacBar 图标

确认 `build/MacBar.app` 正在运行：

```bash
pgrep -fl MacBar
```

如果没有运行，执行：

```bash
./script/build_and_run.sh --verify
```

### 授权后仍显示等待授权

可以先点击应用里的“我已授权，重新检查”。如果仍然无效：

- 确认系统设置中授权的是当前路径的 `build/MacBar.app`。
- 关闭 MacBar 后重新运行 `./script/build_and_run.sh --verify`。
- 在系统设置的辅助功能列表中关闭再打开 MacBar。

### 面板打开但没有其他图标

先确认辅助功能权限已开启。然后点击面板右上角刷新按钮。运行日志中会记录扫描结果，可以查看：

```bash
tail -n 120 /tmp/macbar-debug.log
```

正常情况下会看到类似 `scan completed count=...` 的日志。

### 点击面板里的图标没有反应

MacBar 通过 Accessibility API 调用目标菜单栏元素的 `AXPress` 动作。部分应用可能不暴露可点击的菜单栏元素，或会拒绝辅助功能动作。此时 MacBar 会尝试激活对应应用作为降级处理。

## 开发说明

主要实现点：

- `MenuBarExtra` 负责菜单栏入口和弹出面板。
- `MenuBarManager` 通过 `AXUIElementCreateApplication` 和 `AXExtrasMenuBar` 扫描第三方菜单栏元素。
- `PermissionManager` 使用 `AXIsProcessTrusted` 检查辅助功能权限。
- `MacBarPanelView` 使用 SwiftUI 展示图标网格、刷新按钮、退出按钮和设置入口。

调试时可以直接查看临时日志：

```bash
tail -f /tmp/macbar-debug.log
```

## 说明

MacBar 需要辅助功能权限来读取和操作其他应用的菜单栏元素。请只在你信任的本机环境中构建和运行。
