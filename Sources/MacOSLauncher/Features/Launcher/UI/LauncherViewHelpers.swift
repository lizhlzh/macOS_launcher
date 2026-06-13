import AppKit

enum LauncherTileVisualStyle {
    static func configureIconLayer(_ layer: CALayer?) {
        guard let layer else { return }
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: -6)
        layer.masksToBounds = false
    }

    static func configureTitleLayer(_ layer: CALayer?) {
        guard let layer else { return }
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: -1)
        layer.masksToBounds = false
    }

    static func updateIconShadowPath(for layer: CALayer?, bounds: CGRect) {
        guard let layer else { return }
        layer.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: 18,
            cornerHeight: 18,
            transform: nil
        )
    }
}
