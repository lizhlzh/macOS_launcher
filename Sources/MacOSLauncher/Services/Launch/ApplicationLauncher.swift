import AppKit

/// 抽象应用启动和 Finder 定位能力，避免 `LauncherStore` 直接依赖 Workspace API。
///
/// 调用方向：Launcher UI -> `LauncherStore` -> `ApplicationLaunching`。
@MainActor
protocol ApplicationLaunching: AnyObject {
    /// 启动并激活指定应用。
    ///
    /// - Parameter app: 需要启动的应用元数据。
    func launch(_ app: LauncherAppInfo)

    /// 在 Finder 中显示指定应用包。
    ///
    /// - Parameter app: 需要定位的应用元数据。
    func revealInFinder(_ app: LauncherAppInfo)
}

/// 基于 `NSWorkspace` 的生产环境应用启动器。
@MainActor
final class WorkspaceApplicationLauncher: ApplicationLaunching {
    /// 校验应用路径后异步启动，并记录启动结果。
    ///
    /// - Parameter app: 需要启动的应用元数据。
    func launch(_ app: LauncherAppInfo) {
        let url = URL(fileURLWithPath: app.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            report(ApplicationLaunchError.applicationNotFound(url))
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        LumaEventLog.shared.write(
            "launch.request",
            "id=\(app.id) title=\(app.title) bundle=\(app.bundleIdentifier ?? "nil")"
        )
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) {
            runningApplication,
            error in
            Task { @MainActor in
                if let error {
                    self.report(ApplicationLaunchError.openFailed(url, underlying: error))
                } else {
                    LumaEventLog.shared.write(
                        "launch.result",
                        "id=\(app.id) pid=\(runningApplication?.processIdentifier ?? 0)"
                    )
                }
            }
        }
    }

    /// 在 Finder 中选中应用包。
    ///
    /// - Parameter app: 需要定位的应用元数据。
    func revealInFinder(_ app: LauncherAppInfo) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }

    /// 记录启动错误并播放系统提示音。
    ///
    /// - Parameter error: 需要记录和反馈的启动错误。
    private func report(_ error: Error) {
        LumaEventLog.shared.write("launch.failed", error.localizedDescription)
        NSSound.beep()
    }
}
