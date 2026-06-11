import AppKit
import Carbon

/// 协调应用生命周期、全局服务、菜单和各功能控制器。
///
/// 调用方向：
/// `AppDelegate` -> `AppLifecycleCoordinator`
/// -> `LauncherController` / `SettingsWindowController` / `LauncherStore`
/// -> 扫描、缓存、偏好、权限和登录项服务。
@MainActor
final class AppLifecycleCoordinator {
    private let environment: AppEnvironment
    private let store: LauncherStore
    private let launcherController: LauncherController
    private let settingsController: SettingsWindowController
    private let menuController: MainMenuController

    private var hotKeyManager: HotKeyManager?
    private var eventMonitors: [Any] = []
    private var pinchAccumulator: CGFloat = 0
    private var refreshTask: Task<Void, Never>?

    /// 最近一次全局快捷键错误；属性变化会同步到设置窗口。
    private(set) var hotKeyError: HotKeyRegistrationError? {
        didSet {
            settingsController.updateHotKeyStatus(error: hotKeyError)
        }
    }

    /// 一次性连接回调，使 View 和菜单只发送意图而不直接持有服务。
    ///
    /// - Parameter environment: 包含所有具体服务实现的应用依赖容器。
    init(environment: AppEnvironment) {
        self.environment = environment
        store = LauncherStore(
            preferencesStore: environment.preferencesStore,
            applicationLauncher: environment.applicationLauncher
        )
        launcherController = LauncherController(store: store)
        settingsController = SettingsWindowController(environment: environment)
        menuController = MainMenuController()

        store.onRefreshRequested = { [weak self] in
            self?.refreshApplications()
        }
        settingsController.onRescan = { [weak self] in
            self?.refreshApplications()
        }
        settingsController.onShowLauncher = { [weak self] in
            self?.showLauncher()
        }
        menuController.onShowLauncher = { [weak self] in self?.showLauncher() }
        menuController.onHideLauncher = { [weak self] in self?.launcherController.hide() }
        menuController.onShowSettings = { [weak self] in self?.showSettings() }
        menuController.onRescan = { [weak self] in self?.refreshApplications() }
        menuController.onFocusSearch = { [weak self] in self?.focusSearch() }
        menuController.onRevealLogs = {
            NSWorkspace.shared.activateFileViewerSelecting([
                URL(fileURLWithPath: LumaEventLog.shared.path)
            ])
        }
    }

    /// 启动 Dock 应用行为、全局输入监听、首次展示和状态恢复。
    ///
    /// 由 `AppDelegate.applicationDidFinishLaunching` 调用。
    func start() {
        NSApp.setActivationPolicy(.regular)
        menuController.install()
        configureHotKey()
        configureInputMonitors()
        logPermissions()
        launcherController.show()

        Task { [weak self] in
            await self?.restoreStateAndRefresh()
        }
    }

    /// 取消后台任务，并移除所有进程级事件注册。
    ///
    /// 由 `AppDelegate.applicationWillTerminate` 调用。
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
        hotKeyManager?.unregister()
    }

    /// 通过窗口控制器显示启动器。
    ///
    /// 调用来源包括 Dock 重开、主菜单、设置页、快捷键和捏合手势。
    func showLauncher() {
        launcherController.show()
    }

    /// 显示并激活常驻设置窗口。
    ///
    /// 由应用菜单快捷键 `Command-,` 调用。
    func showSettings() {
        settingsController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 确保启动器可见，然后将键盘焦点转交给搜索框。
    ///
    /// 由“编辑 > 查找”命令 `Command-F` 调用。
    func focusSearch() {
        if !launcherController.isVisible {
            launcherController.show()
        }
        launcherController.focusSearch()
    }

    /// 先恢复偏好和应用缓存，再安排一次后台扫描。
    ///
    /// 数据方向：
    /// `PreferencesStore` + `ApplicationCacheStore` -> `LauncherStore` -> View。
    private func restoreStateAndRefresh() async {
        do {
            let preferences = try await environment.preferencesStore.loadPreferences()
            store.applyPreferences(preferences)
        } catch {
            LumaEventLog.shared.write("preferences.load.failed", error.localizedDescription)
            store.applyPreferences(.empty)
            store.reportPreferencesRecovery(error.localizedDescription)
        }

        do {
            if let cache = try await environment.cacheStore.loadCache() {
                store.applyCachedApplications(cache)
            }
        } catch {
            LumaEventLog.shared.write("cache.load.failed", error.localizedDescription)
        }

        refreshApplications()
    }

    /// 执行一次不可重入的应用扫描，并持久化成功结果。
    ///
    /// 数据方向：
    /// `ApplicationScanner` -> `ApplicationCacheStore` -> `LauncherStore`.
    /// 扫描期间继续展示 Store 中已有内容。
    private func refreshApplications() {
        guard refreshTask == nil else { return }
        store.beginRefreshing()

        let scanner = environment.scanner
        let cacheStore = environment.cacheStore
        refreshTask = Task { [weak self] in
            defer { self?.refreshTask = nil }
            do {
                let result = try await scanner.scanApplications()
                try Task.checkCancellation()
                let scannedAt = Date()
                let cache = ApplicationCache(
                    applications: result.applications,
                    lastScannedAt: scannedAt,
                    schemaVersion: ApplicationCache.currentSchemaVersion
                )
                do {
                    try await cacheStore.saveCache(cache)
                } catch {
                    LumaEventLog.shared.write("cache.save.failed", error.localizedDescription)
                }
                for warning in result.warnings {
                    LumaEventLog.shared.write(
                        "scan.warning",
                        "path=\(warning.path) message=\(warning.message)"
                    )
                }
                self?.store.finishRefreshing(
                    with: result.applications,
                    scannedAt: scannedAt
                )
            } catch is CancellationError {
                LumaEventLog.shared.write("scan.cancelled", "Application scan cancelled.")
            } catch {
                LumaEventLog.shared.write("scan.failed", error.localizedDescription)
                self?.store.failRefreshing(.applicationScan(error.localizedDescription))
            }
        }
    }

    /// 注册 Carbon 全局快捷键，并将注册失败同步到设置页。
    private func configureHotKey() {
        let manager = HotKeyManager(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(controlKey | optionKey)
        ) { [weak self] in
            Task { @MainActor in
                self?.launcherController.toggle()
            }
        }

        do {
            try manager.register()
            hotKeyManager = manager
            hotKeyError = nil
            LumaEventLog.shared.write("hotkey.registered", "Control-Option-Space")
        } catch let error as HotKeyRegistrationError {
            hotKeyManager = manager
            hotKeyError = error
            LumaEventLog.shared.write("hotkey.failed", error.localizedDescription)
        } catch {
            LumaEventLog.shared.write("hotkey.failed", error.localizedDescription)
        }
    }

    /// 安装进程级缩放手势和 Escape 按键监听。
    ///
    /// 事件方向：
    /// `NSEvent` -> coordinator -> `LauncherController`.
    private func configureInputMonitors() {
        let gestureMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            self?.handleMagnify(event)
            return self?.launcherController.isVisible == true ? nil : event
        }

        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .magnify) { [weak self] event in
            self?.handleMagnify(event)
        }

        let escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.launcherController.isVisible == true else {
                return event
            }
            self?.launcherController.handleEscape()
            return nil
        }

        if let gestureMonitor { eventMonitors.append(gestureMonitor) }
        if let globalMonitor { eventMonitors.append(globalMonitor) }
        if let escapeMonitor { eventMonitors.append(escapeMonitor) }
    }

    /// 累加缩放量，超过既有阈值后打开或关闭启动器。
    ///
    /// 阈值属于交互调优参数，修改前必须同时验证全局和窗口内触控板行为。
    ///
    /// - Parameter event: AppKit 传入的缩放手势事件。
    private func handleMagnify(_ event: NSEvent) {
        guard event.type == .magnify else { return }

        if event.phase.contains(.began) {
            pinchAccumulator = 0
        }
        pinchAccumulator += event.magnification

        if !launcherController.isVisible, pinchAccumulator <= -0.35 {
            pinchAccumulator = 0
            launcherController.show()
        } else if launcherController.isVisible, pinchAccumulator >= 0.35 {
            pinchAccumulator = 0
            launcherController.hide()
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            pinchAccumulator = 0
        }
    }

    /// 记录可选权限状态，不因权限不足中断应用启动。
    private func logPermissions() {
        let status = environment.permissionManager.status
        LumaEventLog.shared.write(
            "permissions",
            "accessibility=\(status.accessibilityGranted) "
                + "listenEvents=\(status.inputMonitoringGranted)"
        )
    }
}
