import Foundation

/// 线程安全的进程级本地诊断日志器。
///
/// 调用方向：任意层 -> `LumaEventLog` -> `~/Library/Logs/Luma/events.log`。
final class LumaEventLog: @unchecked Sendable {
    static let shared = LumaEventLog()

    private let lock = NSLock()
    private let fileURL: URL
    private let formatter = ISO8601DateFormatter()

    var path: String {
        fileURL.path
    }

    private init() {
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Luma", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )

        fileURL = logsDirectory.appendingPathComponent("events.log")
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue > 4_000_000 {
            try? FileManager.default.removeItem(at: fileURL)
        }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        write("session", "started pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    /// 追加一条经过换行清洗并带时间戳的日志，不向调用方抛出异常。
    ///
    /// - Parameters:
    ///   - category: 日志分类，用于快速筛选事件类型。
    ///   - message: 延迟求值的日志正文。
    func write(_ category: String, _ message: @autoclosure () -> String) {
        lock.lock()
        defer { lock.unlock() }

        let cleanMessage = message()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let line = "\(formatter.string(from: Date())) [\(category)] \(cleanMessage)\n"
        guard let data = line.data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: fileURL) else {
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }
}
