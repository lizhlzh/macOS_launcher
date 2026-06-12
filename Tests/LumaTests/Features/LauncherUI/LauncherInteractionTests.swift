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
func headerButtonDoesNotDispatchActionWhenDisabled() throws {
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
    button.isEnabled = false
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

    button.mouseDown(with: mouseDown)

    #expect(receiver.invocationCount == 0)
}

@Test
@MainActor
func rootViewRoutesHeaderCoordinatesToHeaderButton() throws {
    let store = makeStore()
    let rootSize = NSSize(width: 1_200, height: 800)
    let rootView = LauncherRootView(
        frame: NSRect(origin: .zero, size: rootSize),
        store: store,
        onClose: { _ in },
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

    let headerWidth = min(max(960, rootSize.width - 260), 1_450)
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

    let hitView = try #require(rootView.hitTest(rawPoint(fromLayoutPoint: sortCenter, in: rootView)))
    #expect(hitView is HeaderButton)
    #expect(hitView.accessibilityLabel() == L10n.text(.sortTooltip))
}

@Test
@MainActor
func pagerHitTestingResolvesExactTileAcrossRowsAndPages() throws {
    let store = makeStore()
    let apps = (0..<80).map { index in
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

    let rootSize = NSSize(width: 1_440, height: 900)
    let rootView = LauncherRootView(
        frame: NSRect(origin: .zero, size: rootSize),
        store: store,
        onClose: { _ in },
        onEscape: {}
    )
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: rootSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = rootView
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }
    rootView.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))

    let pager = try #require(extractPager(from: rootView))
    pager.layoutSubtreeIfNeeded()

    let pagerSize = pager.bounds.size
    let metrics = LauncherGridMetrics(
        size: NSSize(width: pagerSize.width - 96, height: pagerSize.height),
        layout: store.gridLayout
    )

    let firstRowPoint = rootRawPointForPagerPoint(
        tileIconCenter(indexOnPage: 2, metrics: metrics, pager: pager),
        pager: pager,
        rootView: rootView
    )
    let firstRowTile = try #require(rootView.hitTest(firstRowPoint) as? LauncherTileView)
    #expect(firstRowTile.tileID == "app:test.2")

    let secondRowIndex = store.gridLayout.columns + 1
    let secondRowPoint = rootRawPointForPagerPoint(
        tileIconCenter(indexOnPage: secondRowIndex, metrics: metrics, pager: pager),
        pager: pager,
        rootView: rootView
    )
    let secondRowTile = try #require(rootView.hitTest(secondRowPoint) as? LauncherTileView)
    #expect(secondRowTile.tileID == "app:test.\(secondRowIndex)")

    let thirdRowIndex = store.gridLayout.columns * 2 + 3
    let thirdRowPoint = rootRawPointForPagerPoint(
        tileIconCenter(indexOnPage: thirdRowIndex, metrics: metrics, pager: pager),
        pager: pager,
        rootView: rootView
    )
    let thirdRowTile = try #require(rootView.hitTest(thirdRowPoint) as? LauncherTileView)
    #expect(thirdRowTile.tileID == "app:test.\(thirdRowIndex)")

    let lowerRowIndex = store.gridLayout.columns * 3 + 4
    let lowerRowPoint = rootRawPointForPagerPoint(
        tileIconCenter(indexOnPage: lowerRowIndex, metrics: metrics, pager: pager),
        pager: pager,
        rootView: rootView
    )
    let lowerRowTile = try #require(rootView.hitTest(lowerRowPoint) as? LauncherTileView)
    #expect(lowerRowTile.tileID == "app:test.\(lowerRowIndex)")

    let titlePoint = rootRawPointForPagerPoint(
        tileTitleCenter(indexOnPage: lowerRowIndex, metrics: metrics, pager: pager),
        pager: pager,
        rootView: rootView
    )
    let titleTile = try #require(rootView.hitTest(titlePoint) as? LauncherTileView)
    #expect(titleTile.tileID == "app:test.\(lowerRowIndex)")

    store.changePage(by: 1)
    pager.setPage(index: store.pageIndex, dragOffset: 0, animated: false)
    let secondPagePoint = rootRawPointForPagerPoint(
        tileIconCenter(indexOnPage: 1, metrics: metrics, pager: pager),
        pager: pager,
        rootView: rootView
    )
    let secondPageTile = try #require(rootView.hitTest(secondPagePoint) as? LauncherTileView)
    #expect(secondPageTile.tileID == "app:test.\(store.gridLayout.itemsPerPage + 1)")

    store.setGridLayout(rows: 4, columns: 5)
    rootView.layoutSubtreeIfNeeded()
    pager.layoutSubtreeIfNeeded()
    let compactMetrics = LauncherGridMetrics(
        size: NSSize(width: pager.bounds.width - 96, height: pager.bounds.height),
        layout: store.gridLayout
    )
    let compactPoint = rootRawPointForPagerPoint(
        tileIconCenter(indexOnPage: 6, metrics: compactMetrics, pager: pager),
        pager: pager,
        rootView: rootView
    )
    let compactTile = try #require(rootView.hitTest(compactPoint) as? LauncherTileView)
    #expect(compactTile.tileID == "app:test.6")

    store.setSearchText("Test 12")
    rootView.layoutSubtreeIfNeeded()
    pager.layoutSubtreeIfNeeded()
    let searchMetrics = LauncherGridMetrics(
        size: NSSize(width: pager.bounds.width - 96, height: pager.bounds.height),
        layout: store.gridLayout
    )
    let searchPoint = rootRawPointForPagerPoint(
        tileIconCenter(indexOnPage: 0, metrics: searchMetrics, pager: pager),
        pager: pager,
        rootView: rootView
    )
    let searchTile = try #require(rootView.hitTest(searchPoint) as? LauncherTileView)
    #expect(searchTile.tileID == "app:test.12")
}

@Test
@MainActor
func successfulDropIsNotRolledBackWhenDraggingSessionEnds() throws {
    let store = makeStore()
    applyApps((0..<6).map { index in
        LauncherAppInfo(
            id: "app:test.\(index)",
            title: "Test \(index)",
            bundleIdentifier: "test.\(index)",
            path: "/Applications/Test\(index).app"
        )
    }, to: store)

    let rootSize = NSSize(width: 1_440, height: 900)
    let rootView = LauncherRootView(
        frame: NSRect(origin: .zero, size: rootSize),
        store: store,
        onClose: { _ in },
        onEscape: {}
    )
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: rootSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = rootView
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }
    rootView.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))

    let pager = try #require(extractPager(from: rootView))
    pager.layoutSubtreeIfNeeded()

    let source = try #require(pager.debugTileView(withID: "app:test.0"))
    let target = try #require(pager.debugTileView(withID: "app:test.1"))

    pager.tileViewDidBeginDragging(source)
    _ = pager.tileView(target, performDropWith: "app:test.0")
    pager.tileViewDidEndDragging(source)

    #expect(store.folders.count == 1)
    #expect(store.folders[0].itemIDs == ["app:test.0", "app:test.1"])
}

private func tileTitleCenter(
    indexOnPage: Int,
    metrics: LauncherGridMetrics,
    pager _: NSView
) -> NSPoint {
    let row = indexOnPage / metrics.columns
    let column = indexOnPage % metrics.columns
    let tileX = 48 + metrics.leadingInset
        + CGFloat(column) * (metrics.tileWidth + metrics.columnSpacing)
    let tileY = CGFloat(row) * (metrics.tileHeight + metrics.rowSpacing)

    let localPoint = NSPoint(
        x: tileX + metrics.tileWidth / 2,
        y: tileY + metrics.tileVerticalPadding + metrics.iconSize
            + metrics.iconTitleSpacing + metrics.titleHeight / 2
    )
    return localPoint
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
    metrics: LauncherGridMetrics,
    pager _: NSView
) -> NSPoint {
    let row = indexOnPage / metrics.columns
    let column = indexOnPage % metrics.columns
    let tileX = 48 + metrics.leadingInset
        + CGFloat(column) * (metrics.tileWidth + metrics.columnSpacing)
    let tileY = CGFloat(row) * (metrics.tileHeight + metrics.rowSpacing)

    let localPoint = NSPoint(
        x: tileX + metrics.tileWidth / 2,
        y: tileY + metrics.tileVerticalPadding + metrics.iconSize / 2
    )
    return localPoint
}

@MainActor
private func extractPager(from rootView: LauncherRootView) -> LauncherPagerView? {
    Mirror(reflecting: rootView).children
        .first { $0.label == "pager" }?
        .value as? LauncherPagerView
}

@MainActor
private func applyApps(_ apps: [LauncherAppInfo], to store: LauncherStore) {
    store.applyCachedApplications(
        ApplicationCache(
            applications: apps,
            lastScannedAt: Date(),
            schemaVersion: ApplicationCache.currentSchemaVersion
        )
    )
}

@MainActor
private func rawPoint(fromLayoutPoint layoutPoint: NSPoint, in rootView: NSView) -> NSPoint {
    NSPoint(x: layoutPoint.x, y: rootView.bounds.height - layoutPoint.y)
}

@MainActor
private func rootRawPointForPagerPoint(
    _ pagerPoint: NSPoint,
    pager: NSView,
    rootView: NSView
) -> NSPoint {
    let rootLayoutPoint = NSPoint(
        x: pager.frame.minX + pagerPoint.x,
        y: pager.frame.minY + pagerPoint.y
    )
    return rawPoint(fromLayoutPoint: rootLayoutPoint, in: rootView)
}
