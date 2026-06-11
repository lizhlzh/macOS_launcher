import Foundation

/// 定义启动器用户偏好的持久化能力。
///
/// 调用方向：`LauncherStore` / `AppLifecycleCoordinator`
/// -> `PreferencesStoring` -> Application Support 目录中的 JSON 文件。
protocol PreferencesStoring: Sendable {
    /// 加载本地偏好；文件不存在时返回默认值。
    ///
    /// - Returns: 解码后的启动器偏好。
    /// - Throws: 文件读取、备份或 JSON 解码失败时抛出 `PreferencesStoreError`。
    func loadPreferences() async throws -> LauncherPreferences

    /// 以原子写入方式保存偏好。
    ///
    /// - Parameter preferences: 需要持久化的完整偏好快照。
    /// - Throws: 目录创建、编码或文件写入失败时抛出 `PreferencesStoreError`。
    func savePreferences(_ preferences: LauncherPreferences) async throws

    /// 删除当前偏好文件，使下次启动恢复默认配置。
    ///
    /// - Throws: 删除文件失败时抛出 `PreferencesStoreError`。
    func resetPreferences() async throws
}

/// 使用 actor 隔离的 JSON 偏好存储，并支持损坏文件备份。
actor JSONPreferencesStore: PreferencesStoring {
    private let fileManager: FileManager
    private let fileURL: URL

    /// 创建 JSON 偏好存储。
    ///
    /// - Parameters:
    ///   - fileManager: 文件系统操作对象，默认使用系统共享实例。
    ///   - fileURL: 自定义偏好文件路径；为 `nil` 时使用 Luma 的 Application Support 目录。
    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("preferences.json")
    }

    /// 加载并解码偏好；JSON 损坏时先移动到带时间戳的备份文件。
    func loadPreferences() async throws -> LauncherPreferences {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw PreferencesStoreError.fileReadFailed(fileURL, underlying: error)
        }

        do {
            return try JSONDecoder().decode(LauncherPreferences.self, from: data)
        } catch {
            let backupURL = backupCorruptFile()
            throw PreferencesStoreError.decodingFailed(
                fileURL,
                backupURL: backupURL,
                underlying: error
            )
        }
    }

    /// 编码为稳定、可读的 JSON，并以原子方式写入磁盘。
    func savePreferences(_ preferences: LauncherPreferences) async throws {
        try ensureDirectory()
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(preferences)
        } catch {
            throw PreferencesStoreError.encodingFailed(underlying: error)
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw PreferencesStoreError.fileWriteFailed(fileURL, underlying: error)
        }
    }

    /// 删除偏好文件。
    func resetPreferences() async throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                throw PreferencesStoreError.fileWriteFailed(fileURL, underlying: error)
            }
        }
    }

    /// 在首次写入前创建 Application Support 目录。
    private func ensureDirectory() throws {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw PreferencesStoreError.directoryCreationFailed(directory, underlying: error)
        }
    }

    /// 将损坏文件移到备份位置，保留排查依据。
    ///
    /// - Returns: 备份成功后的 URL；备份失败时返回 `nil`。
    private func backupCorruptFile() -> URL? {
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = fileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).json")
        do {
            try fileManager.moveItem(at: fileURL, to: backupURL)
            return backupURL
        } catch {
            LumaEventLog.shared.write("preferences.backup.failed", error.localizedDescription)
            return nil
        }
    }

    /// 计算默认的 Luma Application Support 目录。
    ///
    /// - Parameter fileManager: 用于查询系统目录的文件管理器。
    /// - Returns: 用户 Application Support 下的 Luma 目录，失败时回退到临时目录。
    private static func defaultSupportDirectory(fileManager: FileManager) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Luma", isDirectory: true)
            ?? fileManager.temporaryDirectory.appendingPathComponent("Luma", isDirectory: true)
    }
}
