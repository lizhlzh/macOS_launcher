import AppKit
import Foundation
import Testing
@testable import Luma

@MainActor
private final class DragPreviewApplicationLauncher: ApplicationLaunching {
    func launch(_ app: LauncherAppInfo) {}
    func revealInFinder(_ app: LauncherAppInfo) {}
}

private actor RecordingPreferencesStore: PreferencesStoring {
    private var savedPreferences: [LauncherPreferences] = []

    func loadPreferences() async throws -> LauncherPreferences {
        .empty
    }

    func savePreferences(_ preferences: LauncherPreferences) async throws {
        savedPreferences.append(preferences)
    }

    func resetPreferences() async throws {}

    func saveCount() -> Int {
        savedPreferences.count
    }
}

@Test
@MainActor
func previewMoveTileEmitsDragPreviewChange() {
    let store = makeDragPreviewStore()
    applyDragPreviewApps(to: store)
    var changes: [LauncherStoreChange] = []
    store.onChange = { changes.append($0) }

    store.beginDraggingTile("app:a", commitPolicy: .autoCommit)
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

    store.beginDraggingTile("app:a", commitPolicy: .autoCommit)
    store.previewMoveTile("app:a", before: "app:c")
    store.endDraggingTile(commit: false)

    #expect(store.tileOrder == ["app:a", "app:b", "app:c"])
    #expect(store.draggedTileID == nil)
}

@Test
@MainActor
func quickDragCommitSavesAndExitsEditing() async {
    let preferencesStore = RecordingPreferencesStore()
    let store = LauncherStore(
        preferencesStore: preferencesStore,
        applicationLauncher: DragPreviewApplicationLauncher()
    )
    applyDragPreviewApps(to: store)

    store.beginDraggingTile("app:a", commitPolicy: .autoCommit)
    store.previewMoveTile("app:a", before: "app:c")
    store.endDraggingTile(commit: true)
    await waitForPreferencesSave(on: preferencesStore, expectedCount: 1)

    #expect(store.tileOrder == ["app:b", "app:a", "app:c"])
    #expect(!store.isEditing)
    #expect(store.reorderSessionKind == .none)
}

@Test
@MainActor
func manualEditingDefersSaveUntilCommitted() async {
    let preferencesStore = RecordingPreferencesStore()
    let store = LauncherStore(
        preferencesStore: preferencesStore,
        applicationLauncher: DragPreviewApplicationLauncher()
    )
    applyDragPreviewApps(to: store)

    store.beginManualEditing()
    store.beginDraggingTile("app:a", commitPolicy: .manualCommit)
    store.previewMoveTile("app:a", before: "app:c")
    store.endDraggingTile(commit: true)

    #expect(await preferencesStore.saveCount() == 0)
    #expect(store.tileOrder == ["app:b", "app:a", "app:c"])
    #expect(store.isInManualEditMode)
    #expect(store.isEditing)

    store.commitManualEditing()
    await waitForPreferencesSave(on: preferencesStore, expectedCount: 1)

    #expect(!store.isEditing)
    #expect(store.reorderSessionKind == .none)
}

@Test
@MainActor
func cancelManualEditingRestoresOriginalOrder() async {
    let preferencesStore = RecordingPreferencesStore()
    let store = LauncherStore(
        preferencesStore: preferencesStore,
        applicationLauncher: DragPreviewApplicationLauncher()
    )
    applyDragPreviewApps(to: store)

    store.beginManualEditing()
    store.beginDraggingTile("app:a", commitPolicy: .manualCommit)
    store.previewMoveTile("app:a", before: "app:c")
    store.endDraggingTile(commit: true)
    store.cancelManualEditing()

    #expect(store.tileOrder == ["app:a", "app:b", "app:c"])
    #expect(!store.isEditing)
    #expect(store.reorderSessionKind == .none)
    #expect(await preferencesStore.saveCount() == 0)
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

private func waitForPreferencesSave(
    on preferencesStore: RecordingPreferencesStore,
    expectedCount: Int
) async {
    for _ in 0..<20 {
        if await preferencesStore.saveCount() >= expectedCount {
            return
        }
        try? await Task.sleep(nanoseconds: 25_000_000)
    }
}
