import AppKit

/// Vertically centers single-line text while reserving space for the search icon.
final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    private let textLayoutManager = NSLayoutManager()
    private let leadingInset: CGFloat = 40
    private let trailingInset: CGFloat = 8

    private func centeredTextRect(in bounds: NSRect) -> NSRect {
        guard let font else {
            return bounds
        }

        let lineHeight = ceil(textLayoutManager.defaultLineHeight(for: font))
        return NSRect(
            x: bounds.minX + leadingInset,
            y: floor(bounds.midY - lineHeight / 2),
            width: max(0, bounds.width - leadingInset - trailingInset),
            height: lineHeight
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredTextRect(in: super.titleRect(forBounds: rect))
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredTextRect(in: super.drawingRect(forBounds: rect))
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: centeredTextRect(in: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: centeredTextRect(in: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }
}
