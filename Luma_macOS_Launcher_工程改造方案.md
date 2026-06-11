# Luma macOS Launcher 产品化工程改造方案

## 1. 项目定位

Luma 的目标是开发一个稳定、原生、优雅、可维护的 macOS Launcher 应用，而不是临时 Demo。

本项目按以下边界推进：

| 项目 | 决策 |
|---|---|
| App 形态 | Dock 应用 |
| 产品目标 | 接近 macOS 原生 Launcher 级别体验 |
| 分发方式 | 非 App Store 分发 |
| 数据同步 | 暂不做网络同步 |
| 数据存储 | 全部本地保存 |
| 启动方式 | 支持开机启动 |
| 交互目标 | 稳定、原生、可维护优先；视觉动画保留但不牺牲稳定性 |
| 依赖策略 | 优先使用 macOS 原生能力，不引入不必要第三方依赖 |

---

## 2. 当前代码现状判断

当前代码已经具备 Launcher 的核心能力，包括：

- App 启动入口；
- 全局快捷键；
- 触控板手势；
- 全屏 Launcher Panel；
- 应用扫描；
- 搜索；
- 分页；
- 文件夹；
- 隐藏应用；
- 拖拽排序；
- 右键菜单；
- 本地偏好保存；
- 本地日志。

但现有实现仍然有明显的工程化问题：

1. `AppDelegate` 中直接进行启动组装、权限记录、同步扫描应用、热键注册和事件监听，启动职责过重。
2. `LauncherStore` 同时承担状态管理、应用扫描、偏好读写、图标缓存、应用启动和业务规则，职责过于集中。
3. `LauncherViews.swift` 承载大量 View、菜单、拖拽、文件夹、动画和交互逻辑，不利于维护。
4. 应用扫描目前是同步流程，容易阻塞主线程。
5. 热键注册没有明确错误处理。
6. 偏好文件读写失败处理不足。
7. 拖拽排序存在插入位置和频繁保存问题。
8. Panel 层级和多屏幕策略需要调整。
9. 缺少 Dock 应用应有的菜单、设置、开机启动、权限引导和键盘体验。

---

## 3. 关于 UI 状态：Launcher 是否需要 loading？

结论：**Launcher 不应该把 loading 做成主体验，但仍然需要状态模型。**

Launcher 的使用预期是“瞬时出现、立即可用”。用户按快捷键或点击 Dock 图标时，正常情况下应该直接看到上一次可用的应用列表，而不是每次都看到 loading。

因此状态设计应改为：

```swift
enum LauncherContentState: Equatable {
    case ready
    case refreshing
    case empty
    case failed(LauncherRecoverableError)
}
```

### 3.1 不应显示 loading 的场景

以下场景不应该阻断主界面：

- 普通唤起 Launcher；
- 后台增量扫描应用；
- 后台刷新图标；
- 用户正在翻页、搜索、打开文件夹；
- 上一次缓存可用时的 App 启动。

这些场景应继续展示已有内容，只在角落或状态区显示轻量刷新提示。

示例：

```text
右上角小型状态：Refreshing…
或者设置页中显示：Last scanned 2 minutes ago
```

### 3.2 需要状态提示的场景

以下场景仍然必须有明确状态：

| 场景 | UI 表现 |
|---|---|
| 首次启动且本地没有缓存 | 显示轻量初始化状态 |
| 手动 Rescan | 保留旧结果，同时显示刷新状态 |
| 扫描结果为空 | 显示 Empty 状态和重新扫描按钮 |
| 偏好文件损坏 | 恢复默认配置，并提示用户 |
| 扫描失败 | 显示错误和 Retry |
| 权限不足导致某些交互不可用 | 显示权限引导 |
| 图标加载失败 | 使用默认图标，不阻断主界面 |

### 3.3 推荐策略

启动流程应改成：

1. 先读取本地缓存和偏好；
2. 如果有缓存，立即显示 Launcher；
3. 后台异步扫描应用；
4. 扫描完成后合并结果并刷新 UI；
5. 如果扫描失败，保留旧数据并提示；
6. 如果没有缓存且扫描失败，显示 error；
7. 如果没有缓存且扫描结果为空，显示 empty。

也就是说，状态模型不是为了让 Launcher 每次都 loading，而是为了处理真实产品中的异常、首次启动和恢复场景。

---

## 4. 新工程结构

建议按真实产品工程拆分：

```text
Luma/
  App/
    LumaAppDelegate.swift
    AppEnvironment.swift
    AppLifecycleCoordinator.swift
    MainMenuController.swift

  Core/
    Models/
      LauncherAppInfo.swift
      LauncherFolder.swift
      LauncherTile.swift
      LauncherGridLayout.swift
      LauncherPreferences.swift
      LauncherContentState.swift

    Errors/
      ApplicationScanError.swift
      PreferencesStoreError.swift
      HotKeyRegistrationError.swift
      PermissionError.swift
      ApplicationLaunchError.swift
      LoginItemError.swift

  Services/
    ApplicationScanner/
      ApplicationScanning.swift
      FileSystemApplicationScanner.swift

    Preferences/
      PreferencesStoring.swift
      JSONPreferencesStore.swift

    Cache/
      ApplicationCacheStoring.swift
      JSONApplicationCacheStore.swift

    HotKey/
      HotKeyManaging.swift
      CarbonHotKeyManager.swift

    Permissions/
      PermissionManaging.swift
      MacPermissionManager.swift

    Launch/
      ApplicationLaunching.swift
      WorkspaceApplicationLauncher.swift

    LoginItem/
      LoginItemManaging.swift
      MacLoginItemManager.swift

    Logging/
      EventLogging.swift
      FileEventLogger.swift

  Features/
    Launcher/
      LauncherStore.swift
      LauncherController.swift
      LauncherPanel.swift
      LauncherScreenProvider.swift

    LauncherUI/
      LauncherRootView.swift
      LauncherHeaderView.swift
      LauncherPagerView.swift
      LauncherTileView.swift
      LauncherFolderOverlayView.swift
      LauncherPageDotsView.swift
      LauncherMenuBuilder.swift
      LauncherGridMetrics.swift
      FolderIconRenderer.swift
      HeaderButton.swift

    Settings/
      SettingsWindowController.swift
      GeneralSettingsViewController.swift
      HotKeySettingsViewController.swift
      PermissionSettingsViewController.swift
      AppearanceSettingsViewController.swift
      AdvancedSettingsViewController.swift

  Resources/
    Assets.xcassets
    Info.plist
```

---

## 5. 模块职责边界

## 5.1 App 层

### 职责

负责 App 生命周期和全局协调。

包括：

- 初始化依赖；
- 配置 Dock 应用行为；
- 创建 LauncherController；
- 创建 SettingsWindowController；
- 注册主菜单；
- 配置开机启动状态；
- 处理 Dock 图标点击后的重新打开；
- 处理应用退出。

### 不应该做

- 不直接扫描应用；
- 不直接写偏好文件；
- 不直接处理拖拽排序；
- 不直接构建复杂 UI；
- 不直接调用文件系统扫描逻辑。

### 需要修改

当前启动流程中，`AppDelegate` 同时做了权限记录、创建 Store、同步扫描应用、创建 Controller、注册热键、配置输入监听和显示窗口。应将这些职责拆给 `AppLifecycleCoordinator`。

### 建议设计

```swift
@MainActor
final class AppLifecycleCoordinator {
    private let environment: AppEnvironment
    private let launcherController: LauncherController
    private let settingsController: SettingsWindowController

    init(environment: AppEnvironment) {
        self.environment = environment
        self.launcherController = LauncherController(environment: environment)
        self.settingsController = SettingsWindowController(environment: environment)
    }

    func start() {
        configureMainMenu()
        configureHotKey()
        configureInputMonitors()
        restoreCachedLauncherState()
        refreshApplicationsInBackground()
    }

    func showLauncher() {
        launcherController.show()
    }

    func showSettings() {
        settingsController.showWindow(nil)
    }
}
```

---

## 5.2 LauncherStore

### 职责

`LauncherStore` 只负责 Launcher 业务状态：

- 当前应用列表；
- 当前 Tile 顺序；
- 搜索文本；
- 当前页；
- 当前排序模式；
- 文件夹；
- 隐藏应用；
- 编辑状态；
- 内容状态；
- 用户动作处理。

### 不应该做

- 不直接枚举 `/Applications`；
- 不直接读写 JSON 文件；
- 不直接调用 `NSWorkspace.openApplication`；
- 不直接注册热键；
- 不直接控制 NSPanel；
- 不直接构建右键菜单。

### 需要修改

当前 Store 中的以下能力应拆出：

| 当前能力 | 新模块 |
|---|---|
| 应用扫描 | `ApplicationScanning` |
| 偏好读写 | `PreferencesStoring` |
| 应用缓存读写 | `ApplicationCacheStoring` |
| App 启动 | `ApplicationLaunching` |
| 图标读取 | `ApplicationIconProviding` |
| 日志写入 | `EventLogging` |

### 状态设计

```swift
@MainActor
final class LauncherStore {
    private(set) var apps: [LauncherAppInfo] = []
    private(set) var folders: [LauncherFolder] = []
    private(set) var tileOrder: [String] = []
    private(set) var contentState: LauncherContentState = .ready
    private(set) var searchText: String = ""
    private(set) var pageIndex: Int = 0
    private(set) var isEditing: Bool = false

    var onChange: ((LauncherStoreChange) -> Void)?

    func applyCachedApplications(_ apps: [LauncherAppInfo]) {
        self.apps = apps
        reconcileTilesAfterAppChange()
        contentState = apps.isEmpty ? .empty : .ready
        onChange?(.content(animated: false))
    }

    func beginRefreshing() {
        guard !apps.isEmpty else {
            contentState = .refreshing
            onChange?(.state)
            return
        }

        // 有缓存时不阻断主界面，只做轻量刷新状态。
        contentState = .refreshing
        onChange?(.state)
    }

    func finishRefreshing(with apps: [LauncherAppInfo]) {
        self.apps = apps
        reconcileTilesAfterAppChange()
        contentState = apps.isEmpty ? .empty : .ready
        onChange?(.content(animated: true))
    }

    func failRefreshing(_ error: LauncherRecoverableError) {
        contentState = apps.isEmpty ? .failed(error) : .ready
        onChange?(.state)
    }
}
```

---

## 5.3 ApplicationScanner

### 职责

只负责扫描系统中的 App。

### 扫描范围

默认扫描：

```text
/Applications
~/Applications
/System/Applications
/System/Applications/Utilities
```

后续可支持用户自定义扫描目录。

### 设计要求

- 使用 `async/await`；
- 文件枚举不阻塞主线程；
- 对单个损坏 App 不应导致整体失败；
- 扫描结果要稳定排序；
- 扫描过程不直接操作 UI；
- 对不可访问目录记录 warning。

### 协议

```swift
protocol ApplicationScanning {
    func scanApplications() async throws -> ApplicationScanResult
}

struct ApplicationScanResult: Sendable {
    let applications: [LauncherAppInfo]
    let warnings: [ApplicationScanWarning]
}
```

---

## 5.4 PreferencesStore

### 职责

负责本地偏好读写。

### 存储位置

非 App Store 分发、非 Sandbox 情况下：

```text
~/Library/Application Support/Luma/preferences.json
```

### 保存内容

- 排序模式；
- Tile 顺序；
- 文件夹；
- 网格布局；
- 隐藏应用；
- 快捷键；
- 开机启动偏好；
- 外观偏好。

### 要求

- 使用 `.atomic` 写入；
- 不允许用 `try?` 掩盖失败；
- 配置损坏时备份原文件；
- 读写失败要返回明确错误；
- UI 要能提示用户恢复动作。

### 协议

```swift
protocol PreferencesStoring {
    func loadPreferences() async throws -> LauncherPreferences
    func savePreferences(_ preferences: LauncherPreferences) async throws
}
```

---

## 5.5 ApplicationCacheStore

### 为什么需要缓存

为了让 Launcher 具备“原生级即时唤起体验”，不应每次启动都等待重新扫描应用。

应单独缓存上一次扫描到的应用列表：

```text
~/Library/Application Support/Luma/applications-cache.json
```

### 缓存策略

- App 启动时先读缓存；
- 有缓存立即展示；
- 后台异步刷新；
- 刷新成功后更新缓存；
- 刷新失败时继续使用旧缓存。

### 缓存内容

```swift
struct ApplicationCache: Codable {
    var applications: [LauncherAppInfo]
    var lastScannedAt: Date
    var schemaVersion: Int
}
```

---

## 5.6 HotKeyManager

### 职责

只负责全局快捷键注册、注销和更新。

### 当前问题

热键注册调用 Carbon API，但没有检查 `OSStatus`，注册失败时用户无法感知。

### 修改要求

- 检查 `InstallEventHandler` 返回值；
- 检查 `RegisterEventHotKey` 返回值；
- 注册失败写日志；
- 设置页显示热键状态；
- 用户可以修改快捷键；
- 快捷键冲突时提示用户。

### 错误类型

```swift
enum HotKeyRegistrationError: Error {
    case failedToInstallEventHandler(status: OSStatus)
    case failedToRegisterHotKey(status: OSStatus)
    case failedToUnregister(status: OSStatus)
}
```

---

## 5.7 PermissionManager

### 职责

负责检查和引导权限。

### 需要管理的权限

| 权限 | 用途 | 是否必须 |
|---|---|---|
| Accessibility | 更稳定的全局交互、未来增强控制 | 推荐 |
| Input Monitoring / Listen Event | 全局手势监听 | 视功能而定 |
| Notifications | 后续通知提示 | 可选 |
| Apple Events | 后续控制其他 App | 暂不需要 |

### 策略

- 权限不足不能导致 App 崩溃；
- 权限不足时禁用对应功能；
- 设置页显示权限状态；
- 提供“打开系统设置”按钮；
- 主 Launcher 不应频繁打扰用户。

---

## 5.8 LauncherController 和 LauncherPanel

### 职责

负责窗口生命周期和显示策略。

包括：

- 创建 Panel；
- 显示；
- 隐藏；
- 目标屏幕选择；
- 动画；
- Escape 行为；
- 和 Dock 应用生命周期协作。

### 修改要求

1. Panel 显示到鼠标所在屏幕；
2. 不默认使用过高窗口层级；
3. 支持 Dock 图标点击重新打开；
4. 支持 Command + W / Escape 隐藏；
5. 避免遮挡系统权限弹窗；
6. 全屏应用场景下保持可用。

### 推荐层级

默认使用：

```swift
panel.level = .statusBar
```

如果未来需要极强覆盖能力，可以做成设置项：

```swift
enum LauncherWindowLevel {
    case normal
    case statusBar
    case screenSaver
}
```

但默认不建议 `.screenSaver`。

---

## 5.9 Launcher UI

### 职责

只展示状态和转发用户意图。

### 拆分建议

```text
LauncherRootView
  组合 Header、Pager、Overlay，不写复杂业务

LauncherHeaderView
  搜索、排序、布局、过滤、编辑、刷新、关闭

LauncherPagerView
  分页展示、页面动画、拖拽事件转发

LauncherTileView
  单个应用或文件夹图标展示

LauncherFolderOverlayView
  文件夹内容展示和轻量操作

LauncherMenuBuilder
  构建右键菜单

LauncherGridMetrics
  负责网格布局计算
```

### 交互动作模型

View 不直接修改复杂业务状态，而是发出动作：

```swift
enum LauncherUserAction {
    case searchTextChanged(String)
    case openTile(String)
    case createFolder
    case renameFolder(folderID: String, name: String)
    case deleteFolder(String)
    case addAppToFolder(appID: String, folderID: String)
    case moveTile(draggedID: String, beforeTargetID: String)
    case beginEditing
    case endEditing
    case refreshApplications
    case changeSortMode(SortMode)
    case changeGridLayout(LauncherGridLayout)
    case setAppHidden(appID: String, hidden: Bool)
}
```

---

## 6. Dock 应用体验设计

由于 App 形态确定为 Dock 应用，需要补齐以下 macOS 桌面体验。

## 6.1 Dock 图标行为

### 要求

- 点击 Dock 图标显示 Launcher；
- 如果 Launcher 已显示，则激活窗口；
- 如果用户关闭 Launcher，App 不退出；
- Command + Q 才退出 App；
- Command + , 打开设置。

### AppDelegate 行为

```swift
func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
) -> Bool {
    coordinator.showLauncher()
    return true
}
```

---

## 6.2 主菜单

Dock 应用必须有符合 macOS 习惯的主菜单。

建议菜单：

```text
Luma
  About Luma
  Settings…
  Check Permissions…
  Launch at Login
  Quit Luma

File
  Open Launcher
  Rescan Applications

Edit
  Find
  Clear Search

View
  Sort by Name
  Custom Order
  Increase Grid Density
  Decrease Grid Density
  Reset Layout

Window
  Hide Launcher
  Minimize
  Bring All to Front

Help
  Luma Help
  Reveal Logs
```

---

## 6.3 设置窗口

应使用原生 `NSWindowController` + AppKit ViewController 实现。

设置页：

| 页面 | 内容 |
|---|---|
| General | 开机启动、默认显示屏幕、关闭行为 |
| Hot Key | 快捷键设置、冲突提示 |
| Permissions | 权限状态、打开系统设置 |
| Appearance | 深浅色、视觉效果、网格密度 |
| Advanced | 重扫应用、重置配置、打开日志目录 |

---

## 6.4 开机启动

非 App Store 分发下，建议优先使用现代原生能力：

```swift
SMAppService.mainApp
```

### 策略

- 设置页提供“Launch at Login”开关；
- 注册失败显示错误；
- 不静默失败；
- 不使用第三方登录项库；
- 不建议用老旧 Login Items API。

### 错误类型

```swift
enum LoginItemError: Error {
    case failedToRegister(Error)
    case failedToUnregister(Error)
    case statusUnavailable
}
```

---

## 7. 必须修改内容

## P0：稳定性优先

### 7.1 异步扫描应用

当前同步扫描应用应改为：

- 启动时先读取缓存；
- 有缓存立即显示；
- 后台扫描；
- 扫描成功后刷新；
- 扫描失败保留旧结果。

验收标准：

- 冷启动不假死；
- 应用很多时仍能响应 Dock 点击和快捷键；
- 扫描失败不导致 Launcher 空白；
- 首次无缓存时显示初始化状态。

---

### 7.2 增加应用缓存

为了达到原生 Launcher 级体验，必须增加 `applications-cache.json`。

验收标准：

- 第二次启动几乎立即显示应用列表；
- 后台刷新不会打断用户；
- 卸载或新增 App 后，后台刷新能更新列表；
- 缓存损坏可恢复。

---

### 7.3 修复拖拽排序 bug

当前移动 Tile 时，删除原元素后仍使用旧目标 index，前向后拖动时位置可能错误。

正确策略：

```swift
let moved = tileOrder.remove(at: fromIndex)
let adjustedTargetIndex = fromIndex < toIndex ? toIndex - 1 : toIndex
tileOrder.insert(moved, at: adjustedTargetIndex)
```

验收标准：

```text
[A, B, C, D]
拖 A 到 C 前面
结果必须是 [B, A, C, D]
```

---

### 7.4 拖拽过程中不频繁保存偏好

拖拽更新时只做内存预览，drop 成功后再保存。

需要拆分：

```swift
func previewMoveTile(_ draggedID: String, before targetID: String)
func commitTileOrder() async
func cancelTileMovePreview()
```

验收标准：

- 拖拽不卡顿；
- 拖拽失败可回滚；
- 不在拖拽过程中频繁写 JSON；
- drop 成功后排序持久化。

---

### 7.5 热键注册错误处理

所有 Carbon API 返回值必须检查。

验收标准：

- 快捷键冲突时设置页可见；
- 注册失败有日志；
- 用户可以重新设置快捷键；
- 退出时正确 unregister。

---

### 7.6 偏好读写错误处理

偏好读写必须从 Store 拆出。

验收标准：

- 偏好文件损坏时自动备份；
- 配置恢复默认后提示用户；
- 保存失败时 UI 显示错误；
- 不使用 `try?` 静默失败。

---

### 7.7 多屏幕显示策略

Launcher 应优先显示在鼠标所在屏幕，而不是固定 `NSScreen.main`。

策略：

1. 鼠标所在屏幕；
2. 当前 key window 所在屏幕；
3. main screen；
4. screens.first。

验收标准：

- 双屏下按快捷键显示在当前操作屏；
- 外接屏断开后不出现不可见窗口；
- 全屏空间中表现稳定。

---

### 7.8 窗口层级调整

默认不使用 `.screenSaver`。

建议：

```swift
panel.level = .statusBar
```

验收标准：

- 不遮挡系统授权弹窗；
- 不影响 Command + Tab；
- 能覆盖普通应用窗口；
- 全屏场景下可用。

---

## P1：原生体验补齐

### 7.9 Dock 应用菜单

必须补主菜单，支持：

- Settings；
- Quit；
- Rescan；
- Find；
- Hide Launcher；
- Reveal Logs。

---

### 7.10 设置窗口

必须补设置窗口，至少包括：

- General；
- Hot Key；
- Permissions；
- Appearance；
- Advanced。

---

### 7.11 开机启动

必须支持 Launch at Login。

要求：

- 使用 `SMAppService`；
- 设置页可开关；
- 失败可见；
- 不使用第三方库。

---

### 7.12 键盘操作

必须支持：

| 快捷键 | 行为 |
|---|---|
| Escape | 关闭 Launcher 或退出编辑 |
| Command + F | 聚焦搜索 |
| Command + R | 重扫应用 |
| Command + , | 打开设置 |
| Command + Q | 退出 App |
| Return | 打开选中项 |
| Arrow Keys | 移动选择 |
| Page Up / Page Down | 翻页 |
| Command + W | 隐藏 Launcher |

---

### 7.13 右键菜单增强

现有右键菜单应继续保留，并增加：

- Show in Finder；
- Remove from Folder；
- Rename Folder；
- Delete Folder；
- Hide / Unhide；
- Create New Folder；
- Rescan This App，后续可选。

---

### 7.14 深色 / 浅色模式

当前 UI 中不应大量写死白色和黑色透明度。

要求：

- 使用 `NSColor.labelColor`；
- 使用 `NSColor.secondaryLabelColor`；
- 使用 `NSColor.controlBackgroundColor`；
- 视觉材质随系统 appearance 调整；
- 支持增强对比度。

---

### 7.15 Accessibility

必须补充：

- 按钮 accessibilityLabel；
- Tile accessibilityLabel；
- 文件夹 accessibilityRole；
- 搜索框说明；
- VoiceOver 可读；
- 键盘可达。

---

## P2：产品增强

### 7.16 最近使用

记录最近打开的 App，但要注意隐私。

默认建议：

- 本地记录；
- 设置中可关闭；
- 不上传；
- 不记录精确时间线，只记录排序权重。

---

### 7.17 收藏应用

支持 pin/favorite：

- 收藏页；
- 收藏优先排序；
- 右键 Add to Favorites。

---

### 7.18 自定义扫描目录

非 Sandbox 分发下可以直接支持用户添加目录；若未来启用 Sandbox，则需要 security-scoped bookmark。

---

### 7.19 配置导入导出

支持：

- Export Preferences；
- Import Preferences；
- Reset Preferences。

---

## 8. 本地存储策略

## 8.1 非 Sandbox 默认路径

```text
~/Library/Application Support/Luma/preferences.json
~/Library/Application Support/Luma/applications-cache.json
~/Library/Logs/Luma/events.log
```

## 8.2 数据分类

| 数据 | 文件 | 说明 |
|---|---|---|
| 用户偏好 | preferences.json | 排序、文件夹、网格、隐藏应用、快捷键 |
| 应用缓存 | applications-cache.json | 上次扫描结果 |
| 日志 | events.log | 本地排错 |
| 图标缓存 | 暂不落盘 | 优先内存缓存，后续再评估 |

## 8.3 隐私策略

- 不上传数据；
- 不接入第三方分析；
- 不记录用户打开应用的完整时间线；
- 日志中尽量避免记录完整私人路径；
- 提供清空日志入口；
- 提供重置本地数据入口。

---

## 9. 错误处理策略

必须建立统一错误类型。

```swift
enum PreferencesStoreError: Error {
    case directoryCreationFailed(URL, underlying: Error)
    case fileReadFailed(URL, underlying: Error)
    case fileWriteFailed(URL, underlying: Error)
    case decodingFailed(URL, backupURL: URL?, underlying: Error)
    case encodingFailed(underlying: Error)
}

enum ApplicationScanError: Error {
    case rootUnavailable(URL)
    case enumerationFailed(URL, underlying: Error)
    case cancelled
}

enum ApplicationLaunchError: Error {
    case applicationNotFound(URL)
    case openFailed(URL, underlying: Error)
}

enum HotKeyRegistrationError: Error {
    case failedToInstallEventHandler(status: OSStatus)
    case failedToRegisterHotKey(status: OSStatus)
    case failedToUnregister(status: OSStatus)
}

enum PermissionError: Error {
    case accessibilityDenied
    case listenEventDenied
}

enum LoginItemError: Error {
    case failedToRegister(underlying: Error)
    case failedToUnregister(underlying: Error)
}
```

---

## 10. Sandbox 和权限说明

当前明确为非 App Store 分发，因此第一阶段可以不启用 Sandbox。

但仍应按良好习惯设计：

- 文件读写集中在 Application Support 和 Logs；
- 用户自定义目录功能后续再考虑；
- 不访问用户 Documents、Desktop、Downloads；
- 不做网络请求；
- 不做数据上传；
- 权限不足时不崩溃。

如果未来改为 App Store 或开启 Sandbox，需要重新评估：

- `/Applications` 扫描能力；
- 用户自定义目录访问；
- security-scoped bookmarks；
- Login Item 配置；
- 辅助功能和输入监听审核问题。

---

## 11. 开发阶段计划

## 第一阶段：稳定性修复

目标：修复现有代码中最影响稳定性的问题。

任务：

1. 修复拖拽排序 index bug；
2. 拆出 PreferencesStore；
3. 增加 ApplicationCacheStore；
4. 拆出 ApplicationScanner；
5. 改成异步扫描；
6. 改启动流程：先缓存、后扫描；
7. 修复热键注册错误处理；
8. 调整多屏幕显示策略；
9. 调整 Panel 默认层级；
10. 增加基础错误状态。

验收标准：

- App 启动不卡主线程；
- 第二次启动可立即显示缓存；
- 拖拽排序正确；
- 快捷键失败可见；
- 偏好损坏可恢复；
- 双屏显示正确；
- Launcher 不遮挡系统权限弹窗。

---

## 第二阶段：架构拆分

目标：让代码可长期维护。

任务：

1. 拆分 `LauncherViews.swift`；
2. 拆出 `LauncherMenuBuilder`；
3. 拆出 `LauncherHeaderView`；
4. 拆出 `LauncherFolderOverlayView`；
5. Store 去掉文件扫描、文件读写、App 启动；
6. 建立 Service 协议；
7. 建立统一 Error 类型；
8. 建立基础单元测试。

验收标准：

- View 不直接写复杂业务逻辑；
- Store 职责清晰；
- 文件读写集中；
- 扫描逻辑可测试；
- 拖拽排序可测试；
- 新功能不会继续堆进 RootView。

---

## 第三阶段：Dock 应用产品体验

目标：补齐 macOS Dock 应用应有体验。

任务：

1. 主菜单；
2. 设置窗口；
3. 开机启动；
4. 快捷键设置；
5. 权限引导；
6. 键盘导航；
7. 深浅色模式；
8. Accessibility；
9. Show in Finder；
10. Reveal Logs。

验收标准：

- Dock 点击可打开 Launcher；
- Command + , 打开设置；
- Command + Q 正常退出；
- Launch at Login 可开关；
- 键盘可完成主要操作；
- VoiceOver 可读；
- 深浅色模式正常。

---

## 第四阶段：增强功能

目标：提升产品价值。

任务：

1. 最近使用排序；
2. 收藏应用；
3. 自定义扫描目录；
4. 配置导入导出；
5. 高级搜索；
6. 更细的动画优化；
7. 性能诊断工具。

---

## 12. 最小可行版本范围

基于当前边界，建议 MVP 不是继续加视觉效果，而是先完成：

```text
Dock 应用
全局快捷键唤起
Dock 点击唤起
本地缓存立即显示
后台异步扫描
应用搜索
分页
文件夹
拖拽排序
右键菜单
设置窗口
开机启动
权限引导
偏好恢复
日志
```

暂不做：

```text
网络同步
账号系统
云端配置
插件系统
复杂主题市场
App Store Sandbox
用户行为分析
```

---

## 13. 后续代码输出规则

后续继续开发时，每次输出代码必须遵守：

1. 先说明设计思路；
2. 再给出完整可集成代码；
3. 明确文件路径；
4. 明确替换现有哪段代码；
5. 不写伪代码；
6. 不引入不必要第三方依赖；
7. 不用 `try?` 静默吞错误；
8. 异步任务使用 `Task`、`async/await`、`MainActor` 合理隔离；
9. View 不直接写复杂业务；
10. 代码后说明如何运行和验证。

---

## 14. 推荐立即执行的任务顺序

第一批建议按这个顺序做：

```text
1. 修复 moveTile 排序 bug
2. 拆出 PreferencesStore
3. 新增 ApplicationCacheStore
4. 拆出 FileSystemApplicationScanner
5. 改造启动流程：缓存优先，后台扫描
6. 给 HotKeyManager 增加错误处理
7. 修改 LauncherController 的目标屏幕选择
8. 降低 Panel 默认层级
9. 增加 Dock 应用主菜单
10. 增加 SettingsWindowController 骨架
11. 增加 Launch at Login
12. 拆分 LauncherViews.swift
```

这批完成后，Luma 才适合继续做更精细的动画、视觉风格和增强功能。
