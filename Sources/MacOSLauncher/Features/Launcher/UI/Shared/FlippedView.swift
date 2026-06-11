import AppKit

/// An AppKit container whose origin is at the upper-left corner.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01, bounds.contains(point) else {
            return nil
        }

        for subview in subviews.reversed() where !subview.isHidden && subview.alphaValue > 0.01 {
            let subviewPoint = subview.convert(point, from: self)
            if let hitView = subview.hitTest(subviewPoint) {
                return hitView
            }
        }
        return self
    }
}
