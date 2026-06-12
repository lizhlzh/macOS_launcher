import AppKit
import Foundation
import Testing
@testable import Luma

@MainActor
private final class DragPreviewApplicationLauncher: ApplicationLaunching {
    func launch(_ app: LauncherAppInfo) {}
    func revealInFinder(_ app: LauncherAppInfo) {}
}

@Test
@MainActor
func previewMoveTileEmitsDragPreviewChange() {
    let store = makeDragPreviewStore()
    applyDragPreviewApps(to: store)
    var changes: [LauncherStoreChange] = []
    store.onChange = { changes.append($0) }

    store.beginDraggingTile("app:a")
    store.previewMoveTile("app:a", before: "app:c")

    #expect(store.tileOrder == ["app:b", "app:a", "app:c"])
    #expect(changes.contains { change in
        if case .dragPreview = change {
            return true
        }
        return false
    })
}

@Test
@MainActor
func endDraggingTileRollbackRestoresOriginalOrder() {
    let store = makeDragPreviewStore()
    applyDragPreviewApps(to: store)

    store.beginDraggingTile("app:a")
    store.previewMoveTile("app:a", before: "app:c")
    store.endDraggingTile(commit: false)

    #expect(store.tileOrder == ["app:a", "app:b", "app:c"])
    #expect(store.draggedTileID == nil)
}

@MainActor
private func makeDragPreviewStore() -> LauncherStore {
    let preferencesURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("preferences.json")
    return LauncherStore(
        preferencesStore: JSONPreferencesStore(fileURL: preferencesURL),
        applicationLauncher: DragPreviewApplicationLauncher()
    )
}

@MainActor
private func applyDragPreviewApps(to store: LauncherStore) {
    let apps = [
        LauncherAppInfo(id: "app:a", title: "A", bundleIdentifier: "a", path: "/A.app"),
        LauncherAppInfo(id: "app:b", title: "B", bundleIdentifier: "b", path: "/B.app"),
        LauncherAppInfo(id: "app:c", title: "C", bundleIdentifier: "c", path: "/C.app")
    ]
    store.applyCachedApplications(
        ApplicationCache(
            applications: apps,
            lastScannedAt: Date(),
            schemaVersion: ApplicationCache.currentSchemaVersion
        )
    )
}
