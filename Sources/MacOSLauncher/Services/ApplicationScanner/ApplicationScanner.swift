import Foundation

/// 抽象应用发现能力，使扫描可以脱离 UI 运行并进行测试。
///
/// 调用方向：`AppLifecycleCoordinator` -> `ApplicationScanning`
/// -> `ApplicationScanResult` -> `LauncherStore`.
protocol ApplicationScanning: Sendable {
    /// 枚举已安装应用，不执行任何 UI 操作。
    ///
    /// - Returns: 应用列表及非致命扫描警告。
    /// - Throws: 扫描被取消或没有可用扫描目录时抛出 `ApplicationScanError`。
    func scanApplications() async throws -> ApplicationScanResult
}

/// 在标准本地、用户和系统目录中发现 `.app` 应用包。
struct FileSystemApplicationScanner: ApplicationScanning {
    /// 在独立的后台实用优先级任务中执行文件系统枚举。
    ///
    /// 单个不可访问路径会转换为警告；任务取消会立即终止扫描。
    func scanApplications() async throws -> ApplicationScanResult {
        try await Task.detached(priority: .utility) {
            try Task.checkCancellation()

            let fileManager = FileManager.default
            let roots = applicationSearchRoots(fileManager: fileManager)
            guard !roots.isEmpty else {
                throw ApplicationScanError.noSearchRoots
            }

            var discovered: [LauncherAppInfo] = []
            var seenIDs = Set<String>()
            var warnings: [ApplicationScanWarning] = []

            for root in roots {
                try Task.checkCancellation()
                guard fileManager.fileExists(atPath: root.path) else {
                    warnings.append(.init(path: root.path, message: "Directory is unavailable."))
                    continue
                }

                if root.pathExtension.lowercased() == "app" {
                    appendApp(at: root, to: &discovered, seenIDs: &seenIDs)
                    continue
                }

                guard let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isApplicationKey, .localizedNameKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { url, error in
                        warnings.append(.init(path: url.path, message: error.localizedDescription))
                        return true
                    }
                ) else {
                    warnings.append(.init(path: root.path, message: "Directory could not be enumerated."))
                    continue
                }

                while let url = enumerator.nextObject() as? URL {
                    try Task.checkCancellation()
                    guard url.pathExtension.lowercased() == "app" else {
                        continue
                    }
                    appendApp(at: url, to: &discovered, seenIDs: &seenIDs)
                    enumerator.skipDescendants()
                }
            }

            return ApplicationScanResult(
                applications: discovered.sorted {
                    $0.title.localizedStandardCompare($1.title) == .orderedAscending
                },
                warnings: warnings
            )
        }.value
    }
}

/// 生成并去重默认应用扫描目录。
///
/// - Parameter fileManager: 用于查询系统标准目录的文件管理器。
/// - Returns: 标准化且路径唯一的扫描根目录。
private func applicationSearchRoots(fileManager: FileManager) -> [URL] {
    var roots: [URL] = []
    roots.append(contentsOf: fileManager.urls(for: .applicationDirectory, in: .localDomainMask))
    roots.append(contentsOf: fileManager.urls(for: .applicationDirectory, in: .userDomainMask))
    roots.append(contentsOf: fileManager.urls(for: .applicationDirectory, in: .systemDomainMask))
    roots.append(URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true))

    var unique: [URL] = []
    var seen = Set<String>()
    for root in roots {
        let standardized = root.standardizedFileURL
        if seen.insert(standardized.path).inserted {
            unique.append(standardized)
        }
    }
    return unique
}

/// 将一个应用包转换为稳定应用模型并追加到扫描结果。
///
/// - Parameters:
///   - url: 应用包 URL。
///   - discovered: 当前已发现应用数组。
///   - seenIDs: 用于过滤重复应用的稳定标识集合。
private func appendApp(
    at url: URL,
    to discovered: inout [LauncherAppInfo],
    seenIDs: inout Set<String>
) {
    let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
    let bundle = Bundle(url: canonicalURL)
    let bundleIdentifier = bundle?.bundleIdentifier
    let stableKey = nonEmpty(bundleIdentifier) ?? canonicalURL.path
    let id = "app:\(stableKey)"

    guard seenIDs.insert(id).inserted else {
        return
    }

    discovered.append(
        LauncherAppInfo(
            id: id,
            title: localizedDisplayName(for: bundle, at: canonicalURL),
            bundleIdentifier: bundleIdentifier,
            path: canonicalURL.path
        )
    )
}

/// 解析应用的本地化显示名称。
///
/// - Parameters:
///   - bundle: 应用 Bundle；无法创建时可为 `nil`。
///   - url: 应用包 URL，用于文件名回退。
/// - Returns: 可展示给用户的应用名称。
private func localizedDisplayName(for bundle: Bundle?, at url: URL) -> String {
    let resourceName = try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName
    var fileDisplayName = nonEmpty(resourceName)
        ?? nonEmpty(FileManager.default.displayName(atPath: url.path))
        ?? url.deletingPathExtension().lastPathComponent
    if fileDisplayName.lowercased().hasSuffix(".app") {
        fileDisplayName.removeLast(4)
    }

    return nonEmpty(bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
        ?? nonEmpty(bundle?.localizedInfoDictionary?["CFBundleName"] as? String)
        ?? nonEmpty(bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
        ?? nonEmpty(bundle?.infoDictionary?["CFBundleName"] as? String)
        ?? fileDisplayName
}

/// 去除首尾空白，并将空字符串转换为 `nil`。
///
/// - Parameter value: 待清洗的可选字符串。
/// - Returns: 非空字符串；内容为空时返回 `nil`。
private func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
