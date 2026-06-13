import AppKit

/// 提供指定尺寸的应用图标，并隐藏 `NSWorkspace` 图标缓存细节。
///
/// 调用方向：`LauncherStore` / UI 图标请求 -> `AppIconProviding`。
/// 实现应避免把可变 `size` 状态泄漏到缓存对象。
@MainActor
protocol AppIconProviding {
    func icon(for app: LauncherAppInfo, size: CGFloat) -> NSImage
    func removeIcons(except validAppIDs: Set<String>)
    func clear()
}

/// 基于 `NSWorkspace` 读取应用图标的生产实现。
///
/// 缓存原始图标对象；每次返回指定尺寸的副本，避免不同视图尺寸互相污染。
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

        return sizedCopy(of: baseIcon, size: size)
    }

    func removeIcons(except validAppIDs: Set<String>) {
        iconCache = iconCache.filter { validAppIDs.contains($0.key) }
    }

    func clear() {
        iconCache.removeAll()
    }

    private func sizedCopy(of baseIcon: NSImage, size: CGFloat) -> NSImage {
        let targetSize = NSSize(width: size, height: size)

        if let copy = baseIcon.copy() as? NSImage {
            copy.size = targetSize
            return copy
        }

        let image = NSImage(size: targetSize)
        image.lockFocus()
        baseIcon.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        image.unlockFocus()
        return image
    }
}
