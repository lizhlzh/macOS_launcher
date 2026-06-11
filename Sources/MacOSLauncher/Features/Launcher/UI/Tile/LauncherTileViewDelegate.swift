import AppKit

/// Operations sent from a tile to its owning pager.
@MainActor
protocol LauncherTileViewDelegate: AnyObject {
    func tileView(_ view: LauncherTileView, didRequestOpen tile: LauncherTile)
    func tileViewDidRequestEditing(_ view: LauncherTileView)
    func tileViewDidBeginDragging(_ view: LauncherTileView)
    func tileViewDidEndDragging(_ view: LauncherTileView)
    func tileView(_ view: LauncherTileView, draggingUpdatedWith draggedID: String) -> NSDragOperation
    func tileView(_ view: LauncherTileView, performDropWith draggedID: String) -> Bool
    func tileView(_ view: LauncherTileView, contextMenuFor tile: LauncherTile) -> NSMenu
}
