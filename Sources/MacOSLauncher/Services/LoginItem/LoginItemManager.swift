import ServiceManagement

/// 通过 `SMAppService` 管理主应用的登录启动状态。
@MainActor
final class MacLoginItemManager {
    /// macOS 当前是否报告主应用登录项已启用。
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 注册或注销开机启动。
    ///
    /// - Parameter enabled: `true` 表示启用开机启动，`false` 表示关闭。
    /// - Throws: 注册或注销失败时抛出 `LoginItemError`。
    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            if enabled {
                throw LoginItemError.failedToRegister(underlying: error)
            }
            throw LoginItemError.failedToUnregister(underlying: error)
        }
    }
}
