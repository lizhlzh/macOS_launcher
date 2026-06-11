import AppKit

/// AppKit 应用生命周期入口。
///
/// 调用方向：
/// `NSApplication` -> `AppDelegate` -> `AppLifecycleCoordinator`.
/// 此类型只转发生命周期事件，不承载启动器业务逻辑。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppLifecycleCoordinator!

    /// 创建应用依赖根节点，并启动所有长期运行的服务。
    ///
    /// - Parameter notification: AppKit 发送的应用启动完成通知。
    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppLifecycleCoordinator(environment: AppEnvironment())
        coordinator.start()
    }

    /// 通知协调器取消任务并注销系统级监听。
    ///
    /// - Parameter notification: AppKit 发送的应用即将退出通知。
    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    /// 将 Dock 图标的重新打开事件转发给现有启动器控制器。
    ///
    /// - Parameters:
    ///   - sender: 发起重新打开请求的应用对象。
    ///   - flag: 当前是否已有可见窗口。
    /// - Returns: 始终返回 `true`，表示事件已由 Luma 处理。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.showLauncher()
        return true
    }
}
