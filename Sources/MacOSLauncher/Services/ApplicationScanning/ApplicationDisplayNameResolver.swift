import Foundation

/// Resolves the Finder-facing localized name before consulting bundle metadata.
enum ApplicationDisplayNameResolver {
    static func displayName(
        for url: URL,
        bundle: Bundle?,
        fileManager: FileManager = .default
    ) -> String {
        let resourceLocalizedName = try? url
            .resourceValues(forKeys: [.localizedNameKey])
            .localizedName

        return resolve(
            resourceLocalizedName: resourceLocalizedName,
            fileManagerDisplayName: fileManager.displayName(atPath: url.path),
            localizedInfo: bundle?.localizedInfoDictionary,
            info: bundle?.infoDictionary,
            fallbackName: url.lastPathComponent
        )
    }

    static func resolve(
        resourceLocalizedName: String?,
        fileManagerDisplayName: String?,
        localizedInfo: [String: Any]?,
        info: [String: Any]?,
        fallbackName: String
    ) -> String {
        let candidates = [
            resourceLocalizedName,
            fileManagerDisplayName,
            localizedInfo?["CFBundleDisplayName"] as? String,
            localizedInfo?["CFBundleName"] as? String,
            info?["CFBundleDisplayName"] as? String,
            info?["CFBundleName"] as? String,
            fallbackName
        ]

        return candidates.compactMap(normalizedName).first ?? "Application"
    }

    private static func normalizedName(_ value: String?) -> String? {
        guard var name = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }

        if name.lowercased().hasSuffix(".app") {
            name.removeLast(4)
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name.isEmpty ? nil : name
    }
}
