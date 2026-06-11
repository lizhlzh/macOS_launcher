import Carbon
import Foundation

/// 读取、恢复或写入用户偏好时产生的错误。
enum PreferencesStoreError: LocalizedError {
    case directoryCreationFailed(URL, underlying: Error)
    case fileReadFailed(URL, underlying: Error)
    case fileWriteFailed(URL, underlying: Error)
    case decodingFailed(URL, backupURL: URL?, underlying: Error)
    case encodingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .directoryCreationFailed(url, error):
            "Could not create \(url.path): \(error.localizedDescription)"
        case let .fileReadFailed(url, error):
            "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        case let .fileWriteFailed(url, error):
            "Could not write \(url.lastPathComponent): \(error.localizedDescription)"
        case let .decodingFailed(_, backupURL, error):
            "Preferences were reset because they were invalid. Backup: "
                + "\(backupURL?.path ?? "unavailable"). \(error.localizedDescription)"
        case let .encodingFailed(error):
            "Could not encode preferences: \(error.localizedDescription)"
        }
    }
}

/// 扫描级致命错误；单个不可访问路径只记录为 warning。
enum ApplicationScanError: LocalizedError {
    case noSearchRoots
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noSearchRoots:
            "No application directories are available."
        case .cancelled:
            "Application scanning was cancelled."
        }
    }
}

/// `NSWorkspace` 启动应用之前或过程中产生的错误。
enum ApplicationLaunchError: LocalizedError {
    case applicationNotFound(URL)
    case openFailed(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .applicationNotFound(url):
            "Application no longer exists at \(url.path)."
        case let .openFailed(url, error):
            "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

/// `HotKeyManager` 暴露的 Carbon 状态码错误。
enum HotKeyRegistrationError: LocalizedError {
    case failedToInstallEventHandler(status: OSStatus)
    case failedToRegisterHotKey(status: OSStatus)
    case failedToUnregister(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case let .failedToInstallEventHandler(status):
            "Could not install the hot key event handler (OSStatus \(status))."
        case let .failedToRegisterHotKey(status):
            "The hot key could not be registered, possibly because it is already in use (OSStatus \(status))."
        case let .failedToUnregister(status):
            "The previous hot key could not be unregistered (OSStatus \(status))."
        }
    }
}

/// 注册或注销 `SMAppService.mainApp` 时产生的错误。
enum LoginItemError: LocalizedError {
    case failedToRegister(underlying: Error)
    case failedToUnregister(underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .failedToRegister(error):
            "Could not enable Launch at Login: \(error.localizedDescription)"
        case let .failedToUnregister(error):
            "Could not disable Launch at Login: \(error.localizedDescription)"
        }
    }
}
