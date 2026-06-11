import AppKit
import Foundation
import Testing
@testable import Luma

@MainActor
private final class TestApplicationLauncher: ApplicationLaunching {
    func launch(_ app: LauncherAppInfo) {}
    func revealInFinder(_ app: LauncherAppInfo) {}
}

@MainActor
private final class HeaderActionReceiver: NSObject {
    private(set) var invocationCount = 0

    @objc func invoke(_ sender: Any?) {
        invocationCount += 1
    }
}

@Test
@MainActor
func headerButtonDispatchesOneActionForCompletedClick() throws {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let button = HeaderButton(frame: NSRect(x: 40, y: 25, width: 120, height: 50))
    let receiver = HeaderActionReceiver()
    button.target = receiver
    button.action = #selector(HeaderActionReceiver.invoke(_:))
    window.contentView?.addSubview(button)
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }

    let location = NSPoint(x: button.frame.midX, y: button.frame.midY)
    let mouseDown = try #require(
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: 1,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
    )
    let mouseUp = try #require(
        NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: location,
            modifierFlags: [],
            timestamp: 1.1,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        )
    )

    NSApp.postEvent(mouseUp, atStart: true)
    button.mouseDown(with: mouseDown)

    #expect(receiver.invocationCount == 1)
}

@Test
@MainActor
func rootViewRoutesHeaderCoordinatesToHeaderButton() throws {
    let store = makeStore()
    let rootSize = NSSize(width: 1_200, height: 800)
    let rootView = LauncherRootView(
        frame: NSRect(origin: .zero, size: rootSize),
        store: store,
        onClose: {},
        onEscape: {}
    )
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: rootSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = rootView
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }
    rootView.layoutSubtreeIfNeeded()

    let headerWidth = min(max(900, rootSize.width - 260), 1_450)
    let controlsWidth: CGFloat = 138 + 112 + 58 * 5 + 7 * 6
    let searchWidth = max(320, headerWidth - controlsWidth - 54)
    let headerX = floor((rootSize.width - headerWidth) / 2)
    let reservedTop = max(
        0,
        (window.screen?.frame.maxY ?? 0) - (window.screen?.visibleFrame.maxY ?? 0)
    )
    let headerY = max(62, reservedTop + 18)
    let sortCenter = NSPoint(
        x: headerX + 18 + searchWidth + 10 + 138 / 2,
        y: headerY + 33
    )

    let hitView = try #require(rootView.hitTest(sortCenter))
    #expect(hitView is HeaderButton)
    #expect(hitView.accessibilityLabel() == "Sort")
}

@Test
@MainActor
func pagerHitTestingResolvesExactTileAcrossRowsAndPages() throws {
    let store = makeStore()
    let apps = (0..<40).map { index in
        LauncherAppInfo(
            id: "app:test.\(index)",
            title: "Test \(index)",
            bundleIdentifier: "test.\(index)",
            path: "/Applications/Test\(index).app"
        )
    }
    store.applyCachedApplications(
        ApplicationCache(
            applications: apps,
            lastScannedAt: Date(),
            schemaVersion: ApplicationCache.currentSchemaVersion
        )
    )

    let pagerSize = NSSize(width: 1_000, height: 700)
    let pager = LauncherPagerView(store: store)
    pager.frame = NSRect(origin: .zero, size: pagerSize)
    pager.layoutSubtreeIfNeeded()

    let metrics = LauncherGridMetrics(
        size: NSSize(width: pagerSize.width - 96, height: pagerSize.height),
        layout: store.gridLayout
    )

    let firstRowPoint = tileIconCenter(indexOnPage: 2, metrics: metrics)
    let firstRowTile = try #require(pager.hitTest(firstRowPoint) as? LauncherTileView)
    #expect(firstRowTile.tileID == "app:test.2")

    let lowerRowIndex = store.gridLayout.columns * 3 + 4
    let lowerRowPoint = tileIconCenter(indexOnPage: lowerRowIndex, metrics: metrics)
    let lowerRowTile = try #require(pager.hitTest(lowerRowPoint) as? LauncherTileView)
    #expect(lowerRowTile.tileID == "app:test.\(lowerRowIndex)")

    store.changePage(by: 1)
    pager.setPage(index: store.pageIndex, dragOffset: 0, animated: false)
    let secondPagePoint = tileIconCenter(indexOnPage: 1, metrics: metrics)
    let secondPageTile = try #require(pager.hitTest(secondPagePoint) as? LauncherTileView)
    #expect(secondPageTile.tileID == "app:test.\(store.gridLayout.itemsPerPage + 1)")
}

@MainActor
private func makeStore() -> LauncherStore {
    let preferencesURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("preferences.json")
    return LauncherStore(
        preferencesStore: JSONPreferencesStore(fileURL: preferencesURL),
        applicationLauncher: TestApplicationLauncher()
    )
}

private func tileIconCenter(
    indexOnPage: Int,
    metrics: LauncherGridMetrics
) -> NSPoint {
    let row = indexOnPage / metrics.columns
    let column = indexOnPage % metrics.columns
    let tileX = 48 + metrics.leadingInset
        + CGFloat(column) * (metrics.tileWidth + metrics.columnSpacing)
    let tileY = CGFloat(row) * (metrics.tileHeight + metrics.rowSpacing)

    return NSPoint(
        x: tileX + metrics.tileWidth / 2,
        y: tileY + metrics.tileVerticalPadding + metrics.iconSize / 2
    )
}
