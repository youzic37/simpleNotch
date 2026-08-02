# simpleNotch 项目协作指南

本文档适用于仓库根目录及全部子目录，供在本项目中工作的编码 Agent 使用。修改前先阅读相关实现，不要仅依据文件名推断行为。

## 项目概览

simpleNotch 是一个基于 Boring Notch 的 macOS 菜单栏工具。它将屏幕顶部刘海区域扩展为 SwiftUI 交互面板，提供媒体控制、系统 HUD、日历与提醒事项、摄像头预览、文件 Shelf 和多显示器支持。上游 Sparkle 依赖仍在工程中，但当前发行版已停用自动更新，直到配置本仓库自己的更新密钥和 feed。

- 语言与 UI：Swift 5、SwiftUI、AppKit、Combine；严格并发检查为 `targeted`。
- 部署目标：macOS 14.0。README 当前给出的本地开发环境是 macOS 15.6+、Xcode 26+。
- 工程：`boringNotch.xcodeproj`，主 scheme/target 为 `boringNotch`，构建产物为 `simpleNotch.app`。
- 辅助进程：`BoringNotchXPCHelper`，随主应用嵌入，用于辅助功能授权、屏幕亮度和键盘背光操作。
- 主应用是 `LSUIElement`，通常不显示 Dock 图标；设置和首次启动引导使用独立 AppKit 窗口。
- 当前没有 XCTest 或 UI Test target，也没有 SwiftLint/SwiftFormat 配置。不要声称测试已通过，除非实际执行了对应验证。

## 常用命令

需要完整 Xcode；只有 Command Line Tools 时，`xcodebuild` 无法构建本工程。

```bash
open boringNotch.xcodeproj
```

首次构建或依赖变化后解析 Swift Package：

```bash
xcodebuild \
  -resolvePackageDependencies \
  -project boringNotch.xcodeproj \
  -scheme boringNotch
```

无签名的本地 Debug 构建：

```bash
xcodebuild \
  -project boringNotch.xcodeproj \
  -scheme boringNotch \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/boringNotch-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

提交前至少再执行与 CI 一致的 Release 构建，将上面的 `Debug` 改为 `Release`。基础静态核验可执行：

```bash
plutil -lint boringNotch/Info.plist
plutil -lint boringNotch/boringNotch.entitlements
plutil -lint BoringNotchXPCHelper/Info.plist
plutil -lint BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements
git diff --check
```

DMG 打包位于 `Configuration/dmg/`，预览构建和 GitHub prerelease 由 `.github/workflows/` 管理。除非任务明确涉及发布，不要生成、提交或手工改写发布产物。

## 启动与状态流

理解功能时优先沿以下链路阅读：

1. `boringNotch/boringNotchApp.swift` 中的 `DynamicNotchApp` 创建菜单栏入口；当前不启动 Sparkle updater。
2. `AppDelegate.applicationDidFinishLaunching` 注册屏幕、锁屏、快捷键等观察者，并按设置为一个或所有显示器创建窗口。
3. 每个显示器对应一个 `BoringNotchSkyLightWindow`，内部通过 `NSHostingView` 承载 `ContentView`。
4. `BoringViewModel` 保存单个显示器的开合、尺寸、拖放和摄像头状态；多屏模式下不能把这些状态错误地合并为一个全局实例。
5. `BoringViewCoordinator.shared` 保存跨窗口共享的当前 tab、Sneak Peek、临时 HUD 和部分 `AppStorage` 状态。
6. `ContentView` 组合主界面，并根据 `NotchState`、`NotchViews`、拖放、手势和全局协调状态切换内容。

关键状态职责：

- 窗口创建、屏幕选择、锁屏行为和 DragDetector 生命周期：`AppDelegate`。
- 单屏 UI 状态：`BoringViewModel`。
- 全局 tab 与短时展示状态：`BoringViewCoordinator`。
- 用户设置默认值：`boringNotch/models/Constants.swift` 中的 `Defaults.Keys`。
- 刘海尺寸：`boringNotch/sizing/matters.swift`；计算同时考虑真实刘海、安全区、菜单栏和用户自定义高度。

## 目录与核心模块

- `boringNotch/components/Notch/`：刘海窗口、形状、首页、标题和扩展按钮。
- `boringNotch/components/Settings/`：设置窗口及各设置分区；设置窗口由 `SettingsWindowController.shared` 管理。
- `boringNotch/components/Shelf/`：拖放 Shelf，按 Models / ViewModels / Services / Views 分层。
- `boringNotch/MediaControllers/`：Now Playing、Apple Music、Spotify、YouTube Music 的适配器。
- `boringNotch/managers/MusicManager.swift`：媒体控制器工厂与 UI 所需播放状态的统一出口。
- `boringNotch/managers/`：日历、摄像头、电池、音量、亮度、图片和窗口空间等服务。
- `boringNotch/observers/`：全屏媒体检测、媒体键拦截和扩展拖拽检测。
- `boringNotch/XPCHelperClient/`：主应用侧 XPC 协议与异步客户端。
- `BoringNotchXPCHelper/`：XPC 服务端；该 target 当前关闭 App Sandbox。
- `mediaremote-adapter/`：预编译通用二进制 framework、测试客户端和 Perl 桥接脚本，是 Now Playing 数据链路的一部分。
- `boringNotch/Localizable.xcstrings`：String Catalog；源语言为英文，其他语言由 Crowdin 工作流维护。
- `updater/appcast.xml` 是未启用的上游历史文件；`Configuration/dmg/` 和 `.github/workflows/` 管理预览打包与 CI/CD。

## 开发约定

### Swift、UI 与并发

- 遵循相邻文件的命名和排版；仓库没有统一格式化工具，不要顺手格式化无关代码。
- 触碰 `NSWindow`、`NSScreen`、SwiftUI 发布状态或其他 AppKit UI 对象的代码应在主 actor 上。现有共享 UI 服务多使用 `@MainActor`。
- 长耗时的文件、网络和进程工作放到异步任务或 actor 中；回写 `@Published` 状态时切回主 actor。
- 长生命周期 `Task`、`DispatchWorkItem`、Combine subscription 和通知 observer 必须能取消或移除。闭包捕获共享对象时优先使用 `[weak self]`。
- 保持职责边界：不要把每屏状态放入全局 singleton，也不要在 SwiftUI View 中复制已有 manager/service 的业务逻辑。
- 用户可见行为变化要检查关闭态、打开态、有刘海/无刘海、单屏/多屏四类组合。

### 设置和通知

- 新的持久设置集中定义在 `Defaults.Keys`，需要自定义类型时使其符合 `Defaults.Serializable`。
- 如果设置会影响既有窗口、屏幕或观察器生命周期，应仿照现有实现发布/订阅通知或 `Defaults.publisher`，不能只在设置界面写值。
- 不要随意重命名现有 Defaults/AppStorage key；这些字符串是用户持久数据格式。确需重命名时提供迁移逻辑，参考首选显示器 UUID 的迁移。

### 媒体控制

- 所有新媒体源实现 `MediaControllerProtocol`，通过 `playbackStatePublisher` 提供统一的 `PlaybackState`。
- 添加控制器时同时更新 `MediaControllerType`、`MusicManager.createController`、设置/引导 UI 和所需权限。
- `NowPlayingController` 依赖私有 `MediaRemote.framework`、仓库内 Perl 脚本和预编译 adapter；`SkyLightWindow` 也使用私有 SkyLight API。修改这类代码必须保留失败回退，并在支持的 macOS 版本和 Intel/Apple Silicon 上验证。
- Apple Music 与 Spotify 控制会触发 Apple Events；更改目标应用或权限需求时同步检查 entitlements 和 Info.plist build settings。

### XPC 与系统权限

- `BoringNotchXPCHelperProtocol.swift` 在主应用和 XPC target 中各有一份。修改方法签名时必须同步两份协议，并同时更新 `XPCHelperClient` 和 `BoringNotchXPCHelper` 实现。
- XPC 接口只能使用 Objective-C/XPC 可编码的参数类型。异步 Swift 包装应留在客户端，不要直接暴露无法桥接的 Swift 类型。
- 不要无意扩大 sandbox entitlement、Mach lookup、Apple Events、相机、日历、网络或文件权限。新增受保护资源时，同时更新对应 usage description 并做拒绝授权路径测试。
- 系统 HUD 依赖辅助功能授权和媒体键拦截；授权失败时必须保持可恢复，并停用相关设置或观察器。

### Shelf 与文件访问

- Shelf 的唯一可变数据源是 `ShelfStateViewModel.shared`，修改 `items` 会由 `ShelfPersistenceService` 原子写入 Application Support。
- 沙盒外文件必须通过 security-scoped bookmark 处理。使用 `Bookmark`、`URL+SecurityScoped` 和现有 resolve/update 方法，不要持久化裸文件路径替代 bookmark。
- 添加、拖出、分享和删除项目时保留去重、临时文件清理、stale bookmark 刷新及分享期间阻止刘海关闭的行为。
- 若修改 `ShelfItem` 的 Codable 结构，要考虑旧 `items.json` 的兼容与部分损坏数据恢复。

### 本地化、资源和工程文件

- SwiftUI 的用户可见英文字符串会由 String Catalog 提取。不要手工翻译或改写 `Localizable.xcstrings` 中的非英文内容；翻译通过 Crowdin 提交。
- 新增资源应放入合适的 asset catalog 或现有资源目录，确认 Copy Bundle Resources 和运行时查找名称一致。
- 主应用大部分目录仍使用显式 PBXGroup：仅在文件系统创建 Swift 文件通常不会自动加入 target，必须通过 Xcode 或谨慎修改 `project.pbxproj` 添加文件引用与 Sources build phase。
- `boringNotch/private/` 和整个 `BoringNotchXPCHelper/` 使用 file-system-synchronized group，行为与其他目录不同。不要因为这两个目录可自动同步就假定全工程都可自动同步。
- 新增或升级第三方依赖时提交一致的 `Package.resolved`，并检查 `THIRD_PARTY_LICENSES` 是否需要更新。

## 验证要求

按改动范围执行最小但充分的验证：

- 所有代码改动：无签名 Debug 构建；提交前尽量补 Release 构建。
- 窗口/布局：真实运行后验证 hover、点击、上下滑手势、自动关闭、全屏、锁屏相关路径；涉及多屏时连接或模拟不同显示器布局。
- 媒体：验证对应媒体源的播放/暂停、切歌、进度、封面、空闲状态；不要用一个控制器的结果代表全部媒体源。
- HUD/XPC：验证授权未决定、允许、拒绝和授权被撤销；验证音量、屏幕亮度、键盘背光的不可用回退。
- Shelf：验证文件/文本/链接拖入、重启后恢复、重复项目、删除、Quick Look/分享，以及原文件移动或权限失效。
- 日历/相机：验证首次授权、拒绝授权和系统设置中重新授权。
- 本地化/UI：至少检查英文和一种较长文本语言下的截断；UI 变化在 PR 中提供截图或录屏。
- 发布相关：只使用仓库 workflow 和 `Configuration/dmg` 的既有路径，额外核验版本号、`simpleNotch.app` 名称、内嵌 XPC、framework、adapter 脚本和签名状态。当前 workflow 只能发布明确标注为 ad-hoc、未公证的 prerelease。

如果受当前环境限制无法运行某项验证，应在交付说明中明确写出未运行的命令、原因和仍需人工检查的风险。

## 提交与范围控制

- 分支和 PR 以 `WuTao-maker/simpleNotch` 仓库当前规则为准；不要照搬上游专用的 `dev` → `main` 发布流程。
- 保持改动聚焦，不修改无关格式、版本号、appcast、签名配置或二进制依赖。
- 不覆盖用户已有的工作区改动。提交前检查 `git status` 和 `git diff`，确认没有 DerivedData、签名材料、临时媒体或本地偏好文件。
- UI 变更附截图或录屏；权限、持久化和私有 API 变更在说明中列出兼容性与回退行为。
