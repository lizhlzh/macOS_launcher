import Foundation

/// 持有应用使用的具体服务实现，是整个工程的依赖容器。
///
/// 调用方向：
/// `AppDelegate` 创建 `AppEnvironment`，随后 `AppLifecycleCoordinator`
/// 将服务注入功能控制器和状态 Store。
@MainActor
final class AppEnvironment {
    let scanner: any ApplicationScanning
    let preferencesStore: any PreferencesStoring
    let cacheStore: any ApplicationCacheStoring
    let applicationLauncher: any ApplicationLaunching
    let appIconProvider: any AppIconProviding
    let permissionManager: MacPermissionManager
    let loginItemManager: MacLoginItemManager

    /// 创建生产环境依赖图，同时允许测试传入替代实现。
    ///
    /// - Parameters:
    ///   - scanner: 应用扫描服务。
    ///   - preferencesStore: 用户偏好存储服务。
    ///   - cacheStore: 应用扫描缓存服务。
    ///   - applicationLauncher: 应用启动和 Finder 定位服务。
    ///   - appIconProvider: 应用图标读取和缓存服务。
    ///   - permissionManager: 系统权限状态和跳转服务。
    ///   - loginItemManager: 开机启动管理服务。
    init(
        scanner: any ApplicationScanning = FileSystemApplicationScanner(),
        preferencesStore: any PreferencesStoring = JSONPreferencesStore(),
        cacheStore: any ApplicationCacheStoring = JSONApplicationCacheStore(),
        applicationLauncher: any ApplicationLaunching = WorkspaceApplicationLauncher(),
        appIconProvider: any AppIconProviding = WorkspaceAppIconProvider(),
        permissionManager: MacPermissionManager = MacPermissionManager(),
        loginItemManager: MacLoginItemManager = MacLoginItemManager()
    ) {
        self.scanner = scanner
        self.preferencesStore = preferencesStore
        self.cacheStore = cacheStore
        self.applicationLauncher = applicationLauncher
        self.appIconProvider = appIconProvider
        self.permissionManager = permissionManager
        self.loginItemManager = loginItemManager
    }
}
