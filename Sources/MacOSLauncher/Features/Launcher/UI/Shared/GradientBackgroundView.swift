import AppKit
import QuartzCore

/// A Core Animation-backed gradient used by the launcher background.
final class GradientBackgroundView: NSView {
    var colors: [NSColor] = [] {
        didSet {
            gradientLayer.colors = colors.map(\.cgColor)
        }
    }

    private let gradientLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = gradientLayer
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
