import AppKit

@MainActor
protocol AppIconProviding {
    func icon(for app: LauncherAppInfo, size: CGFloat) -> NSImage
    func removeIcons(except validAppIDs: Set<String>)
    func clear()
}

@MainActor
final class WorkspaceAppIconProvider: AppIconProviding {
    private var iconCache: [String: NSImage] = [:]

    func icon(for app: LauncherAppInfo, size: CGFloat) -> NSImage {
        let baseIcon: NSImage
        if let cached = iconCache[app.id] {
            baseIcon = cached
        } else {
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            iconCache[app.id] = icon
            baseIcon = icon
        }

        guard let copy = baseIcon.copy() as? NSImage else {
            baseIcon.size = NSSize(width: size, height: size)
            return baseIcon
        }

        copy.size = NSSize(width: size, height: size)
        return copy
    }

    func removeIcons(except validAppIDs: Set<String>) {
        iconCache = iconCache.filter { validAppIDs.contains($0.key) }
    }

    func clear() {
        iconCache.removeAll()
    }
}
