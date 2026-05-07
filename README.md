# MacBar

MacBar 是一个 macOS 菜单栏图标聚合代理工具。它常驻在系统菜单栏中，扫描其他第三方菜单栏应用的真实菜单栏项，并在 MacBar 面板里用一行横向工具条集中代理操作，减少菜单栏拥挤。

## 功能

- 常驻 macOS 菜单栏，点击 MacBar 图标打开一行聚合面板。
- 自动扫描第三方菜单栏图标，并用一行横向工具条显示图标；已授予屏幕录制权限时优先使用当前菜单栏截图裁剪出的真实图标，否则安静回退到应用图标。
- 点击面板中的应用图标，会通过 Accessibility API 触发对应真实菜单栏项的菜单。
- 面板会按图标数量自动扩展宽度，不显示横向滚动条；图标过多超出屏幕时仍可横向滑动。
- 默认会尝试把已经聚合到面板里的第三方原菜单栏图标移出可见区域，失败时保留原图标但不影响面板代理操作。
- 支持刷新当前菜单栏图标列表。
- 支持从聚合列表中排除指定应用，并可在设置中恢复。
- 支持自动刷新、点击后自动收起延迟、排除/恢复应用等 2.0 选项。
- 内置辅助功能权限引导页，授权后会自动重新检查权限。
- 纯菜单栏应用模式运行，不显示 Dock 图标。

<img width="559" height="81" alt="image" src="https://github.com/user-attachments/assets/6e13b4cd-62c1-42c8-bb6e-5db7cc18aa5d" />

## 系统要求

- macOS 13.0 或更高版本。
- Xcode 命令行工具或完整 Xcode。
- 可用的 Apple Development 签名证书。
- 需要授予辅助功能权限，否则无法读取和操作其他应用的菜单栏元素。
- 如果希望面板图标完全贴近原菜单栏图标，可额外授予屏幕录制权限；未授权时 MacBar 不会弹窗打断，会使用应用图标兜底。

## 项目结构

```text
MacBar/
├── MacBar.xcodeproj/       # Xcode 工程
├── MacBar/                 # Swift 源码
│   ├── MacBarApp.swift     # 应用入口和 MenuBarExtra
│   ├── AppDelegate.swift   # 应用生命周期、权限轮询、设置窗口
│   ├── MenuBarManager.swift # 菜单栏扫描、聚合过滤和代理点击逻辑
│   ├── MacBarPanelView.swift # 2.0 一行横向聚合面板 UI
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

MacBar 通过 Accessibility API 调用目标菜单栏元素的 `AXPress` 动作。部分应用可能不暴露可点击的菜单栏元素，或会拒绝辅助功能动作。此时 MacBar 会显示轻量状态提示，并尝试激活对应应用作为降级处理。

### MacBar 是否真的把其他 App 的图标搬进来了？

不是字面意义上的搬移。macOS 不提供稳定公共 API 将其他进程的 `NSStatusItem` view 重新挂载到 MacBar 的 SwiftUI 层级。MacBar 2.0 的实现是“聚合代理”：读取真实菜单栏项，使用自己的横向面板展示对应入口，并在点击时代理触发原菜单栏项。

## 开发说明

主要实现点：

- `MenuBarExtra` 负责菜单栏入口和一行聚合面板。
- `MenuBarManager` 通过 `AXUIElementCreateApplication` 和 `AXExtrasMenuBar` 扫描第三方菜单栏元素，并负责排除列表和代理点击。
- `PermissionManager` 使用 `AXIsProcessTrusted` 检查辅助功能权限。
- `MacBarPanelView` 使用 SwiftUI 展示横向图标条、刷新按钮、退出按钮和设置入口。

调试时可以直接查看临时日志：

```bash
tail -f /tmp/macbar-debug.log
```

## 说明

MacBar 需要辅助功能权限来读取和操作其他应用的菜单栏元素。请只在你信任的本机环境中构建和运行。
