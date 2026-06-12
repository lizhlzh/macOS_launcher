import AppKit
import Foundation

enum LumaLogCategory: String {
    case lifecycle
    case header
    case hitTest
    case tile
    case drag
    case page
    case search
    case folder
    case performance
}

func lumaLogPoint(_ point: NSPoint) -> String {
    String(format: "%.1f,%.1f", point.x, point.y)
}

func lumaLogSize(_ size: CGSize) -> String {
    String(format: "%.1f,%.1f", size.width, size.height)
}

func lumaLogRect(_ rect: NSRect) -> String {
    "\(lumaLogPoint(rect.origin));\(lumaLogSize(rect.size))"
}

func lumaLogOptional(_ value: (any CustomStringConvertible)?) -> String {
    guard let value else {
        return "nil"
    }
    return String(describing: value)
}

/// 线程安全的进程级本地诊断日志器。
///
/// 调用方向：任意层 -> `LumaEventLog` -> `~/Library/Logs/Luma/luma.log`。
final class LumaEventLog: @unchecked Sendable {
    static let shared = LumaEventLog()

    let sessionID = UUID().uuidString

    private let fileManager = FileManager.default
    private let logsDirectory: URL
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.local.Luma.event-log", qos: .utility)
    private let formatter = ISO8601DateFormatter()
    private let maxFileSize = 5_000_000
    private let maxRotatedFiles = 3

    var path: String {
        fileURL.path
    }

    var isInteractionLoggingEnabled: Bool {
        !UserDefaults.standard.bool(forKey: "LumaInteractionLoggingDisabled")
    }

    private init() {
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        logsDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Luma", isDirectory: true)
        fileURL = logsDirectory.appendingPathComponent("luma.log")

        queue.async { [weak self] in
            self?.prepareLogFileIfNeeded()
            self?.writeLineSync(
                self?.buildLine(
                    category: "lifecycle",
                    event: "logging.started",
                    fields: [
                        "enabled": self?.isInteractionLoggingEnabled.description ?? "false",
                        "path": self?.path ?? "",
                        "maxSize": "5000000",
                        "rotationCount": "\(self?.maxRotatedFiles ?? 0)"
                    ]
                ) ?? ""
            )
            self?.writeLineSync(
                self?.buildLine(
                    category: "lifecycle",
                    event: "logging.path",
                    fields: [
                        "path": self?.path ?? "",
                        "sessionID": self?.sessionID ?? ""
                    ]
                ) ?? ""
            )
        }
    }

    func write(_ category: String, _ message: @autoclosure @escaping () -> String) {
        let evaluatedMessage = sanitize(message())
        queue.async { [weak self] in
            guard let self else { return }
            let line = self.buildLine(
                category: category,
                event: nil,
                fields: ["message": evaluatedMessage]
            )
            self.writeLineSync(line)
        }
    }

    func writeInteraction(
        _ category: LumaLogCategory,
        _ event: String,
        fields: [String: (any CustomStringConvertible)?] = [:]
    ) {
        guard isInteractionLoggingEnabled else {
            return
        }

        let prepared = fields.reduce(into: [String: String]()) { partialResult, item in
            partialResult[item.key] = sanitizeOptional(item.value)
        }
        queue.async { [weak self] in
            guard let self else { return }
            let line = self.buildLine(
                category: category.rawValue,
                event: event,
                fields: prepared
            )
            self.writeLineSync(line)
        }
    }

    private func prepareLogFileIfNeeded() {
        try? fileManager.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    private func buildLine(category: String, event: String?, fields: [String: String]) -> String {
        var parts = [
            formatter.string(from: Date()),
            "category=\(sanitize(category))"
        ]
        if let event {
            parts.append("event=\(sanitize(event))")
        }
        parts.append("sessionID=\(sanitize(sessionID))")
        parts.append("thread=\(Thread.isMainThread ? "main" : "background")")
        parts.append("mainThread=\(Thread.isMainThread)")

        for key in fields.keys.sorted() {
            guard let value = fields[key], !value.isEmpty else { continue }
            parts.append("\(sanitize(key))=\(sanitize(value))")
        }
        return parts.joined(separator: " ") + "\n"
    }

    private func writeLineSync(_ line: String) {
        guard !line.isEmpty else {
            return
        }

        prepareLogFileIfNeeded()
        guard let data = line.data(using: .utf8) else {
            return
        }
        rotateIfNeeded(adding: data.count)

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private func rotateIfNeeded(adding byteCount: Int) {
        let size = ((try? fileManager.attributesOfItem(atPath: fileURL.path)[.size]) as? NSNumber)?.intValue ?? 0
        guard size + byteCount > maxFileSize else {
            return
        }

        let oldestURL = rotatedFileURL(index: maxRotatedFiles)
        if fileManager.fileExists(atPath: oldestURL.path) {
            try? fileManager.removeItem(at: oldestURL)
        }

        for index in stride(from: maxRotatedFiles - 1, through: 0, by: -1) {
            let sourceURL = index == 0 ? fileURL : rotatedFileURL(index: index)
            let destinationURL = rotatedFileURL(index: index + 1)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                continue
            }
            try? fileManager.removeItem(at: destinationURL)
            try? fileManager.moveItem(at: sourceURL, to: destinationURL)
        }

        fileManager.createFile(atPath: fileURL.path, contents: nil)
    }

    private func rotatedFileURL(index: Int) -> URL {
        logsDirectory.appendingPathComponent("luma.\(index).log")
    }

    private func sanitizeOptional(_ value: (any CustomStringConvertible)?) -> String {
        guard let value else {
            return "nil"
        }
        return sanitize(String(describing: value))
    }

    private func sanitize(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\"", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return "\"\""
        }
        if cleaned.rangeOfCharacter(from: .whitespacesAndNewlines) != nil || cleaned.contains("=") {
            return "\"\(cleaned)\""
        }
        return cleaned
    }
}
