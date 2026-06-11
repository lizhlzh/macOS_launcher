import AppKit
import Foundation
import Testing
@testable import Luma

@MainActor
private final class FolderTestApplicationLauncher: ApplicationLaunching {
    func launch(_ app: LauncherAppInfo) {}
    func revealInFinder(_ app: LauncherAppInfo) {}
}

@Test
@MainActor
func appToAppDropCreatesFolderAndRemovesBothTopLevelApps() {
    let store = makeFolderTestStore()
    applyTestApps(to: store)

    store.createFolder(containingAppIDs: ["app:a", "app:b"])

    #expect(store.folders.count == 1)
    #expect(store.folders[0].itemIDs == ["app:a", "app:b"])
    #expect(store.visibleTiles.map(\.id).contains(store.folders[0].tileID))
    #expect(!store.visibleTiles.map(\.id).contains("app:a"))
    #expect(!store.visibleTiles.map(\.id).contains("app:b"))
}

@Test
@MainActor
func appCanBeAddedToExistingFolder() {
    let store = makeFolderTestStore()
    applyTestApps(to: store)
    let folder = store.createFolder(named: "Work", containing: ["app:a"])

    store.addApp("app:b", to: folder.id)

    #expect(store.folder(withID: folder.id)?.itemIDs == ["app:a", "app:b"])
    #expect(!store.visibleTiles.map(\.id).contains("app:b"))
}

@Test
@MainActor
func invalidApplicationIDsDoNotMutateFolderState() {
    let store = makeFolderTestStore()
    applyTestApps(to: store)
    let folder = store.createFolder(named: "Work", containing: ["app:a"])
    let foldersBefore = store.folders
    let orderBefore = store.tileOrder

    store.addApp("app:missing", to: folder.id)
    store.createFolder(containingAppIDs: ["app:a", "app:missing"])

    #expect(store.folders == foldersBefore)
    #expect(store.tileOrder == orderBefore)
}

@Test
@MainActor
func draggingUpdatesCustomTileOrder() {
    let store = makeFolderTestStore()
    applyTestApps(to: store)

    store.beginDraggingTile("app:a")
    store.previewMoveTile("app:a", before: "app:c")
    store.endDraggingTile(commit: true)

    #expect(store.tileOrder == ["app:b", "app:a", "app:c"])
}

@Test
@MainActor
func searchPreventsDragReordering() {
    let store = makeFolderTestStore()
    applyTestApps(to: store)
    let originalOrder = store.tileOrder
    store.setSearchText("A")

    store.beginDraggingTile("app:a")
    store.previewMoveTile("app:a", before: "app:c")
    store.endDraggingTile(commit: true)

    #expect(store.tileOrder == originalOrder)
}

@MainActor
private func makeFolderTestStore() -> LauncherStore {
    let preferencesURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("preferences.json")
    return LauncherStore(
        preferencesStore: JSONPreferencesStore(fileURL: preferencesURL),
        applicationLauncher: FolderTestApplicationLauncher()
    )
}

@MainActor
private func applyTestApps(to store: LauncherStore) {
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
