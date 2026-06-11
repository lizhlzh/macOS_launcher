import AppKit

extension NSView {
    var enclosingLauncherTileView: LauncherTileView? {
        var current: NSView? = self
        while let view = current {
            if let tileView = view as? LauncherTileView {
                return tileView
            }
            current = view.superview
        }
        return nil
    }
}
