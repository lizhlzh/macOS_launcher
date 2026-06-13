import AppKit

enum LauncherTileVisualStyle {
    static let iconShadowOpacity: Float = 0.28
    static let iconShadowRadius: CGFloat = 12
    static let iconShadowOffset = CGSize(width: 0, height: -6)

    static let titleShadowOpacity: Float = 0.45
    static let titleShadowRadius: CGFloat = 2
    static let titleShadowOffset = CGSize(width: 0, height: -1)

    static func configureIconLayer(_ layer: CALayer?) {
        guard let layer else { return }
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = iconShadowOpacity
        layer.shadowRadius = iconShadowRadius
        layer.shadowOffset = iconShadowOffset
        layer.masksToBounds = false
        layer.shadowPath = nil
    }

    static func configureTitleLayer(_ layer: CALayer?) {
        guard let layer else { return }
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = titleShadowOpacity
        layer.shadowRadius = titleShadowRadius
        layer.shadowOffset = titleShadowOffset
        layer.masksToBounds = false
        layer.shadowPath = nil
    }
}
