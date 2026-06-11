import Foundation

/// 定义最近一次成功扫描结果的缓存能力。
///
/// 调用方向：`AppLifecycleCoordinator` -> 缓存服务 -> `LauncherStore`。
protocol ApplicationCacheStoring: Sendable {
    /// 加载与当前数据结构版本兼容的应用缓存。
    ///
    /// - Returns: 可用缓存；文件不存在、损坏或版本不兼容时返回 `nil`。
    /// - Throws: 无法完成必要文件操作时抛出错误。
    func loadCache() async throws -> ApplicationCache?

    /// 原子保存最近一次成功扫描结果。
    ///
    /// - Parameter cache: 包含应用列表、扫描时间和数据结构版本的缓存。
    /// - Throws: 目录创建、编码或写入失败时抛出错误。
    func saveCache(_ cache: ApplicationCache) async throws
}

/// 使用 actor 隔离并校验数据结构版本的 JSON 应用缓存。
actor JSONApplicationCacheStore: ApplicationCacheStoring {
    private let fileManager: FileManager
    private let fileURL: URL

    /// 创建应用缓存存储。
    ///
    /// - Parameters:
    ///   - fileManager: 文件系统操作对象，默认使用系统共享实例。
    ///   - fileURL: 自定义缓存路径；为 `nil` 时使用 Luma 的 Application Support 目录。
    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("Luma", isDirectory: true)
            ?? fileManager.temporaryDirectory.appendingPathComponent("Luma", isDirectory: true)
        self.fileURL = fileURL ?? supportDirectory.appendingPathComponent("applications-cache.json")
    }

    /// 只返回数据结构版本匹配的缓存；损坏缓存会被删除并重建。
    func loadCache() async throws -> ApplicationCache? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cache = try decoder.decode(ApplicationCache.self, from: data)
            guard cache.schemaVersion == ApplicationCache.currentSchemaVersion else {
                return nil
            }
            return cache
        } catch {
            LumaEventLog.shared.write("cache.invalid", error.localizedDescription)
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                LumaEventLog.shared.write("cache.remove.failed", error.localizedDescription)
            }
            return nil
        }
    }

    /// 成功刷新后以原子方式保存扫描结果。
    func saveCache(_ cache: ApplicationCache) async throws {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw PreferencesStoreError.fileWriteFailed(fileURL, underlying: error)
        }
    }
}
