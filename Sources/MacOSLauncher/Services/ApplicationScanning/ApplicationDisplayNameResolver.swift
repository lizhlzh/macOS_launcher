import Foundation

/// Resolves the Finder-facing localized name before consulting bundle metadata.
enum ApplicationDisplayNameResolver {
    static func displayName(
        for url: URL,
        bundle: Bundle?,
        fileManager: FileManager = .default,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let resourceLocalizedName = try? url
            .resourceValues(forKeys: [.localizedNameKey])
            .localizedName
        let bundleURL = bundle?.bundleURL ?? url
        let bundleIdentifier = bundle?.bundleIdentifier
        let preferredInfoPlistName = localizedInfoPlistValue(
            for: bundleURL,
            preferredLocalizations: localizationCandidates(from: preferredLanguages),
            keys: ["CFBundleDisplayName", "CFBundleName"]
        )

        return resolve(
            resourceLocalizedName: resourceLocalizedName,
            fileManagerDisplayName: fileManager.displayName(atPath: url.path),
            preferredLocalizedInfoPlistName: preferredInfoPlistName,
            localizedInfo: bundle?.localizedInfoDictionary,
            info: bundle?.infoDictionary,
            bundleIdentifier: bundleIdentifier,
            fallbackName: url.lastPathComponent
        )
    }

    static func resolve(
        resourceLocalizedName: String?,
        fileManagerDisplayName: String?,
        preferredLocalizedInfoPlistName: String? = nil,
        localizedInfo: [String: Any]?,
        info: [String: Any]?,
        bundleIdentifier: String? = nil,
        fallbackName: String
    ) -> String {
        let candidates = [
            resourceLocalizedName,
            fileManagerDisplayName,
            preferredLocalizedInfoPlistName,
            localizedInfo?["CFBundleDisplayName"] as? String,
            localizedInfo?["CFBundleName"] as? String,
            info?["CFBundleDisplayName"] as? String,
            info?["CFBundleName"] as? String,
            fallbackName
        ]
        let resolved = candidates.compactMap(normalizedName).first ?? "Application"
        return knownLocalizedOverride(name: resolved, bundleIdentifier: bundleIdentifier) ?? resolved
    }

    private static func localizationCandidates(from preferredLanguages: [String]) -> [String] {
        var candidates: [String] = []

        for language in preferredLanguages {
            let normalized = language.replacingOccurrences(of: "_", with: "-")
            let components = normalized.split(separator: "-").map(String.init)
            if !normalized.isEmpty {
                candidates.append(normalized)
                candidates.append(normalized.replacingOccurrences(of: "-", with: "_"))
            }
            if let base = components.first, !base.isEmpty {
                candidates.append(base)
            }
            if components.count >= 2 {
                let twoPart = "\(components[0])-\(components[1])"
                candidates.append(twoPart)
                candidates.append(twoPart.replacingOccurrences(of: "-", with: "_"))
            }
        }

        if preferredLanguages.contains(where: { $0.lowercased().hasPrefix("zh") }) {
            candidates.append(contentsOf: ["zh-Hans", "zh_CN", "zh", "zh-Hant", "zh_TW"])
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.lowercased()
            return !candidate.isEmpty && seen.insert(key).inserted
        }
    }

    private static func localizedInfoPlistValue(
        for bundleURL: URL,
        preferredLocalizations: [String],
        keys: [String]
    ) -> String? {
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        for localization in preferredLocalizations {
            let localizationBundleURL = resourcesURL.appendingPathComponent("\(localization).lproj", isDirectory: true)
            guard let localizationBundle = Bundle(path: localizationBundleURL.path) else {
                continue
            }
            for key in keys {
                let value = localizationBundle.localizedString(forKey: key, value: nil, table: "InfoPlist")
                if value != key, let normalized = normalizedName(value) {
                    return normalized
                }
            }
        }
        return nil
    }

    private static func knownLocalizedOverride(
        name: String,
        bundleIdentifier: String?
    ) -> String? {
        let normalizedName = name.lowercased()
        let normalizedBundleID = bundleIdentifier?.lowercased() ?? ""

        if normalizedBundleID.contains("baidu") && normalizedBundleID.contains("netdisk") {
            return "百度网盘"
        }
        if normalizedName == "baidunetdisk" {
            return "百度网盘"
        }

        if normalizedBundleID.contains("tencent") && normalizedBundleID.contains("meeting") {
            return "腾讯会议"
        }
        if normalizedName == "tencentmeeting" {
            return "腾讯会议"
        }

        return nil
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
