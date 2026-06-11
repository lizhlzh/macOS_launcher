import AppKit
import ApplicationServices
import CoreGraphics

/// 启动器相关可选系统权限的当前快照。
struct PermissionStatus {
    let accessibilityGranted: Bool
    let inputMonitoringGranted: Bool
}

/// 读取权限状态，并跳转到对应的系统设置页面。
@MainActor
final class MacPermissionManager {
    /// 每次读取时返回最新权限快照。
    var status: PermissionStatus {
        PermissionStatus(
            accessibilityGranted: AXIsProcessTrusted(),
            inputMonitoringGranted: CGPreflightListenEventAccess()
        )
    }

    /// 打开“辅助功能”权限设置。
    func openAccessibilitySettings() {
        openSystemSettings(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    /// 打开“输入监控”权限设置。
    func openInputMonitoringSettings() {
        openSystemSettings(
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
    }

    /// 打开指定系统设置深层链接。
    ///
    /// - Parameter value: `x-apple.systempreferences` URL 字符串。
    private func openSystemSettings(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
