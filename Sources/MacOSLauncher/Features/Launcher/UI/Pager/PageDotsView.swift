import AppKit

/// Draws pagination dots and translates clicks into page selections.
final class PageDotsView: NSView {
    var pageCount = 1 {
        didSet { needsDisplay = true }
    }
    var currentPage = 0 {
        didSet { needsDisplay = true }
    }
    var onSelect: ((Int) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let count = max(1, pageCount)
        let spacing: CGFloat = 14
        let totalWidth = CGFloat(count - 1) * spacing + 8
        let startX = floor((bounds.width - totalWidth) / 2)
        for index in 0..<count {
            let size: CGFloat = index == currentPage ? 8 : 6
            let rect = NSRect(
                x: startX + CGFloat(index) * spacing,
                y: floor((bounds.height - size) / 2),
                width: size,
                height: size
            )
            (index == currentPage
                ? NSColor.white.withAlphaComponent(0.92)
                : NSColor.white.withAlphaComponent(0.34)
            ).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let count = max(1, pageCount)
        let spacing: CGFloat = 14
        let totalWidth = CGFloat(count - 1) * spacing + 8
        let startX = floor((bounds.width - totalWidth) / 2)
        let point = convert(event.locationInWindow, from: nil)
        let index = Int(round((point.x - startX) / spacing))
        guard index >= 0, index < count else { return }
        onSelect?(index)
    }
}
