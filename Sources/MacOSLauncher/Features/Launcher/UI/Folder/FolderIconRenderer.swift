import AppKit

/// Renders a composite folder icon from up to four applications.
enum FolderIconRenderer {
    @MainActor
    static func image(apps: [LauncherAppInfo], store: LauncherStore, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        let border = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: size * 0.22,
            yRadius: size * 0.22
        )
        border.lineWidth = 1
        border.stroke()

        let gap = size * 0.07
        let inset = size * 0.13
        let cell = (size - inset * 2 - gap) / 2
        for index in 0..<4 {
            let row = index / 2
            let column = index % 2
            let cellRect = NSRect(
                x: inset + CGFloat(column) * (cell + gap),
                y: size - inset - cell - CGFloat(row) * (cell + gap),
                width: cell,
                height: cell
            )
            if index < apps.count {
                store.appIcon(for: apps[index], size: cell).draw(in: cellRect)
            } else {
                NSColor.white.withAlphaComponent(0.09).setFill()
                NSBezierPath(
                    roundedRect: cellRect,
                    xRadius: cell * 0.18,
                    yRadius: cell * 0.18
                ).fill()
            }
        }
        return image
    }
}
