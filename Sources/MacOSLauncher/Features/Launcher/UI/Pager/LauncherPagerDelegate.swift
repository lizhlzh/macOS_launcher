import AppKit

/// Operations sent from the pager to the root launcher view.
@MainActor
protocol LauncherPagerDelegate: AnyObject {
    func pager(_ pager: LauncherPagerView, open tile: LauncherTile)
    func pagerDidRequestEditing(_ pager: LauncherPagerView)
    func pager(_ pager: LauncherPagerView, contextMenuFor tile: LauncherTile) -> NSMenu
}
