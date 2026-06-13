import AppKit
import QuartzCore

/// 渲染分页 Tile、交互式页面移动、边缘副本和拖拽预览。
///
/// 数据方向：
/// `LauncherStore.visibleTiles` -> 页面视图和 Tile 视图。
/// 手势方向：
/// 状态容器中的页面偏移 -> `setPage` -> `contentView` 的坐标原点。
/// 拖拽方向：
/// Tile/Pager 放置回调 -> Store 预览 -> 一次提交或回滚。
@MainActor
final class LauncherPagerView: NSView {
    weak var delegate: LauncherPagerDelegate?

    private let store: LauncherStore
    private let contentView = FlippedView()
    private let leadingReplica = LauncherReplicaPageView()
    private let trailingReplica = LauncherReplicaPageView()
    private var pageViews: [Int: FlippedView] = [:]
    private var tileViews: [String: LauncherTileView] = [:]
    private var activeTileIDs = Set<String>()
    private var metrics = LauncherGridMetrics(size: .zero, layout: .default)
    private var lastBoundsSize: CGSize = .zero
    private var dropTargetID: String?
    private var renderedPageCount = 1
    private var settleGeneration = 0
    private var pageRasterizationEnabled = true
    private var replicaRefreshWorkItem: DispatchWorkItem?
    private let horizontalContentInset: CGFloat = 48
    private var interactionSuspensionGeneration = 0
    private var isInteractionSuspended = false
    private var dragPreviewScheduled = false
    private var needsDragPreviewAfterCurrentPass = false
    private var currentDragCommitted = false
    private var isFolderDropTarget = false
    private var edgePageWorkItem: DispatchWorkItem?
    private var edgePageDirection: Int = 0
    private var lastDragWindowLocation: NSPoint?
    private let interactionLogThrottle = InteractionLogThrottle()

    override var isFlipped: Bool { true }

    /// 创建分页视图。
    ///
    /// - Parameter store: 提供 Tile、分页、编辑和拖拽状态的业务 Store。
    init(store: LauncherStore) {
        self.store = store
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        contentView.wantsLayer = true
        contentView.layer?.drawsAsynchronously = true
        addSubview(contentView)

        for replica in [leadingReplica, trailingReplica] {
            replica.wantsLayer = true
            replica.layer?.drawsAsynchronously = true
            contentView.addSubview(replica)
        }
        registerForDraggedTypes([.string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard bounds.size != lastBoundsSize else { return }
        lastBoundsSize = bounds.size
        reload(animated: false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }
        if isInteractionSuspended {
            if interactionLogThrottle.shouldLog("pager.hitTest.suspended", interval: 0.15) {
                LumaEventLog.shared.writeInteraction(
                    .hitTest,
                    "pager.hitTest.begin",
                    fields: [
                        "pointInPager": lumaLogPoint(point),
                        "bounds": lumaLogRect(bounds),
                        "isInteractionSuspended": isInteractionSuspended,
                        "pageIndex": store.pageIndex,
                        "renderedPageCount": renderedPageCount,
                        "contentOrigin": lumaLogPoint(contentView.frame.origin),
                        "contentSize": lumaLogSize(contentView.frame.size),
                        "pageViews": pageViews.keys.sorted().map(String.init).joined(separator: ",")
                    ]
                )
            }
            return self
        }

        if interactionLogThrottle.shouldLog("pager.hitTest.begin", interval: 0.15) {
            LumaEventLog.shared.writeInteraction(
                .hitTest,
                "pager.hitTest.begin",
                fields: [
                    "pointInPager": lumaLogPoint(point),
                    "bounds": lumaLogRect(bounds),
                    "isInteractionSuspended": isInteractionSuspended,
                    "pageIndex": store.pageIndex,
                    "renderedPageCount": renderedPageCount,
                    "contentOrigin": lumaLogPoint(contentView.frame.origin),
                    "contentSize": lumaLogSize(contentView.frame.size),
                    "pageViews": pageViews.keys.sorted().map(String.init).joined(separator: ",")
                ]
            )
        }
        if let tileView = hitTestTile(at: point, from: self),
           activeTileIDs.contains(tileView.tileID),
           tileView.alphaValue > 0.05 {
            if interactionLogThrottle.shouldLog("pager.hitTest.result.\(tileView.tileID)", interval: 0.30) {
                LumaEventLog.shared.writeInteraction(
                    .hitTest,
                    "pager.hitTest.result",
                    fields: [
                        "result": "tile",
                        "tileID": tileView.tileID
                    ]
                )
            }
            return tileView
        }
        if interactionLogThrottle.shouldLog("pager.hitTest.nil", interval: 0.15) {
            LumaEventLog.shared.writeInteraction(.hitTest, "pager.hitTest.result", fields: ["result": "nil"])
        }
        return nil
    }

    /// 根据 Store 状态协调 Tile 视图，并可选地对差异执行动画。
    ///
    /// - Parameter animated: 是否为新增、删除和位置变化执行动画。
    func reload(animated: Bool) {
        let start = CACurrentMediaTime()
        replicaRefreshWorkItem?.cancel()
        replicaRefreshWorkItem = nil
        if animated {
            setPageRasterizationEnabled(true)
            performReload(animated: true, refreshReplicas: false, retargetRunningAnimations: true)
            scheduleRenderStabilization(after: 0.18)
        } else {
            setPageRasterizationEnabled(true)
            performReload(animated: false, refreshReplicas: true, retargetRunningAnimations: false)
        }
        LumaEventLog.shared.writeInteraction(
            .performance,
            "pager.reload",
            fields: [
                "animated": animated,
                "durationMS": Int((CACurrentMediaTime() - start) * 1_000)
            ]
        )
    }

    func reloadSearchResults() {
        replicaRefreshWorkItem?.cancel()
        setPageRasterizationEnabled(true)
        performReload(animated: false, refreshReplicas: true, retargetRunningAnimations: false)
    }

    func reloadForLayoutChange() {
        let start = CACurrentMediaTime()

        replicaRefreshWorkItem?.cancel()
        replicaRefreshWorkItem = nil

        contentView.wantsLayer = true
        contentView.alphaValue = 1
        contentView.layer?.removeAnimation(forKey: "layoutTransition")
        contentView.layer?.removeAnimation(forKey: "layoutChangeScale")
        contentView.layer?.transform = CATransform3DIdentity
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        setPageRasterizationEnabled(false)
        if !reduceMotion {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.24
            transition.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.80, 0.22, 1.0)
            contentView.layer?.add(transition, forKey: "layoutTransition")
        }

        performReload(animated: false, refreshReplicas: false, retargetRunningAnimations: false)

        if !reduceMotion, let layer = contentView.layer {
            let scale = CABasicAnimation(keyPath: "transform")
            scale.fromValue = NSValue(caTransform3D: CATransform3DMakeScale(0.97, 0.97, 1))
            scale.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            scale.duration = 0.24
            scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.80, 0.22, 1.0)
            layer.transform = CATransform3DIdentity
            layer.add(scale, forKey: "layoutChangeScale")
            scheduleEdgeReplicaRefresh(after: 0.42)
        } else {
            scheduleEdgeReplicaRefresh(after: 0.25)
        }

        LumaEventLog.shared.writeInteraction(
            .performance,
            "pager.reloadForLayoutChange",
            fields: [
                "durationMS": Int((CACurrentMediaTime() - start) * 1_000),
                "tiles": store.visibleTiles.count,
                "pages": renderedPageCount,
                "reduceMotion": reduceMotion ? "true" : "false"
            ]
        )
    }

    func reloadForFilterModeChange(from previousPageIndex: Int, to targetPageIndex: Int) {
        replicaRefreshWorkItem?.cancel()
        replicaRefreshWorkItem = nil
        setPageRasterizationEnabled(true)
        performReload(animated: false, refreshReplicas: false, retargetRunningAnimations: false)

        let startPage = min(max(0, previousPageIndex), max(0, renderedPageCount - 1))
        contentView.setFrameOrigin(NSPoint(x: -CGFloat(startPage + 1) * bounds.width, y: 0))

        if startPage != targetPageIndex, renderedPageCount > 1 {
            setPage(
                index: targetPageIndex,
                dragOffset: 0,
                animated: true,
                previousIndex: startPage,
                previousOffset: 0
            )
        } else {
            setPage(index: targetPageIndex, dragOffset: 0, animated: false)
        }

        scheduleEdgeReplicaRefresh(after: 0.35)
    }

    func reloadForFolderCreation(from previousPageIndex: Int, to targetPageIndex: Int) {
        replicaRefreshWorkItem?.cancel()
        replicaRefreshWorkItem = nil
        setPageRasterizationEnabled(true)
        performReload(animated: false, refreshReplicas: false, retargetRunningAnimations: false)

        let startPage = min(max(0, previousPageIndex), max(0, renderedPageCount - 1))
        let targetPage = min(max(0, targetPageIndex), max(0, renderedPageCount - 1))
        contentView.setFrameOrigin(NSPoint(x: -CGFloat(startPage + 1) * bounds.width, y: 0))

        if startPage != targetPage, renderedPageCount > 1 {
            let previousOffset: CGFloat = startPage < targetPage ? -1 : 1
            setPage(
                index: targetPage,
                dragOffset: 0,
                animated: true,
                previousIndex: startPage,
                previousOffset: previousOffset
            )
        } else {
            setPage(index: targetPage, dragOffset: 0, animated: false)
        }

        scheduleEdgeReplicaRefresh(after: 0.35)
    }

    func scheduleDragPreviewAnimation() {
        if dragPreviewScheduled {
            needsDragPreviewAfterCurrentPass = true
            return
        }

        dragPreviewScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.dragPreviewScheduled = false
            self.applyDragPreview()

            if self.needsDragPreviewAfterCurrentPass {
                self.needsDragPreviewAfterCurrentPass = false
                self.scheduleDragPreviewAnimation()
            }
        }
    }

    private func scheduleRenderStabilization(after delay: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.setPageRasterizationEnabled(true)
            self.refreshEdgeReplicas()
            self.replicaRefreshWorkItem = nil
        }
        replicaRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleEdgeReplicaRefresh(after delay: TimeInterval) {
        replicaRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.setPageRasterizationEnabled(true)
            self.refreshEdgeReplicas()
            self.replicaRefreshWorkItem = nil
        }
        replicaRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// 在视图位置动画过程中暂时停止命中测试。
    ///
    /// - Parameter duration: 暂停交互的秒数。
    func suspendInteraction(for duration: TimeInterval) {
        interactionSuspensionGeneration += 1
        let generation = interactionSuspensionGeneration
        isInteractionSuspended = true
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.interactionSuspensionGeneration == generation else {
                return
            }
            self.isInteractionSuspended = false
        }
    }

    /// 按 Tile 标识复用视图、更新所属页面，并对差异执行动画。
    ///
    /// 此方法是核心渲染协调器，只读取 Store，不修改业务数据。
    ///
    /// - Parameters:
    ///   - animated: 是否执行重排和透明度动画。
    ///   - refreshReplicas: 是否立即刷新首尾页面副本。
    ///   - retargetRunningAnimations: 是否从当前展示层状态重新定向动画。
    private func performReload(
        animated: Bool,
        refreshReplicas: Bool,
        retargetRunningAnimations: Bool
    ) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let start = CACurrentMediaTime()

        metrics = LauncherGridMetrics(
            size: CGSize(
                width: max(320, bounds.width - horizontalContentInset * 2),
                height: bounds.height
            ),
            layout: store.gridLayout
        )
        let tiles = store.visibleTiles
        let targetIDs = Set(tiles.map(\.id))
        activeTileIDs = targetIDs
        let removed = tileViews.filter {
            !targetIDs.contains($0.key) && $0.value.isDescendant(of: contentView)
        }
        let removedViews = removed.map(\.value)

        for (_, view) in removed {
            if !animated {
                view.removeFromSuperview()
            }
        }

        if animated, !removedViews.isEmpty {
            if retargetRunningAnimations {
                removedViews.forEach(prepareForAnimationRetarget)
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for view in removedViews {
                    view.animator().alphaValue = 0
                }
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    for view in removedViews
                    where !self.store.visibleTiles.contains(where: { $0.id == view.tileID }) {
                        view.removeFromSuperview()
                    }
                }
            }
        }

        let pageCount = max(1, Int(ceil(Double(tiles.count) / Double(metrics.itemsPerPage))))
        renderedPageCount = pageCount
        let contentWidth = CGFloat(pageCount + 2) * bounds.width
        var contentFrame = contentView.frame
        contentFrame.size = NSSize(width: contentWidth, height: bounds.height)
        contentView.frame = contentFrame

        let obsoletePages = pageViews.keys.filter { $0 >= pageCount }
        for pageIndex in obsoletePages {
            pageViews.removeValue(forKey: pageIndex)?.removeFromSuperview()
        }

        for pageIndex in 0..<pageCount {
            let pageView: FlippedView
            if let existing = pageViews[pageIndex] {
                pageView = existing
            } else {
                pageView = FlippedView()
                pageView.wantsLayer = true
                pageView.layer?.drawsAsynchronously = true
                pageView.layer?.shouldRasterize = pageRasterizationEnabled
                pageViews[pageIndex] = pageView
                contentView.addSubview(pageView)
            }

            pageView.frame = NSRect(
                x: CGFloat(pageIndex + 1) * bounds.width,
                y: 0,
                width: bounds.width,
                height: bounds.height
            )
            pageView.layer?.rasterizationScale = backingScaleFactor
        }

        var movingViews: [(view: LauncherTileView, frame: NSRect)] = []
        var appearingViews: [LauncherTileView] = []
        for (index, tile) in tiles.enumerated() {
            let pageIndex = index / metrics.itemsPerPage
            guard let pageView = pageViews[pageIndex] else {
                continue
            }

            let view: LauncherTileView
            let isNew: Bool
            if let existing = tileViews[tile.id] {
                view = existing
                isNew = !view.isDescendant(of: contentView)
                view.update(tile: tile, metrics: metrics, showJiggle: store.shouldShowJiggle)
                if isNew {
                    view.alphaValue = animated ? 0 : 1
                }
            } else {
                view = LauncherTileView(
                    tile: tile,
                    store: store,
                    metrics: metrics,
                    showJiggle: store.shouldShowJiggle
                )
                view.delegate = self
                view.alphaValue = animated ? 0 : 1
                tileViews[tile.id] = view
                pageView.addSubview(view)
                isNew = true
            }

            if view.superview !== pageView {
                pageView.addSubview(view)
            }

            let frame = frameForTile(at: index)
            if animated && !isNew {
                if retargetRunningAnimations {
                    prepareForAnimationRetarget(view)
                }
                movingViews.append((view, frame))
            } else {
                view.frame = frame
            }

            if animated && (isNew || view.alphaValue < 0.999) {
                appearingViews.append(view)
            }
        }

        if animated, !movingViews.isEmpty || !appearingViews.isEmpty {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.22,
                    0.72,
                    0.30,
                    1.0
                )
                for movement in movingViews {
                    movement.view.animator().frame = movement.frame
                }
                for view in appearingViews {
                    view.animator().alphaValue = 1
                }
            }
        }

        for pageView in pageViews.values {
            pageView.layoutSubtreeIfNeeded()
        }
        if refreshReplicas {
            refreshEdgeReplicas()
        }
        if refreshReplicas, animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                self?.refreshEdgeReplicas()
            }
        }

        setPage(index: store.pageIndex, dragOffset: store.pageDragOffset, animated: false)
        LumaEventLog.shared.writeInteraction(
            .performance,
            "pager.performReload",
            fields: [
                "animated": animated,
                "tiles": tiles.count,
                "pages": pageCount,
                "durationMS": Int((CACurrentMediaTime() - start) * 1_000)
            ]
        )
    }

    private func prepareForAnimationRetarget(_ view: NSView) {
        guard let layer = view.layer,
              let presentation = layer.presentation() else {
            return
        }

        let visibleFrame = presentation.frame
        let visibleAlpha = CGFloat(presentation.opacity)
        layer.removeAllAnimations()
        view.frame = visibleFrame
        view.alphaValue = visibleAlpha
    }

    private func setPageRasterizationEnabled(_ enabled: Bool) {
        pageRasterizationEnabled = enabled
        let scale = backingScaleFactor
        for pageView in pageViews.values {
            pageView.layer?.shouldRasterize = enabled
            pageView.layer?.rasterizationScale = scale
        }
    }

    func updateEditingState() {
        for view in tileViews.values {
            view.setEditing(store.shouldShowJiggle, dragged: store.draggedTileID == view.tileID)
        }
    }

    /// 将页面条定位到直接拖动位置或动画归位位置。
    ///
    /// 首尾页面副本用于实现循环翻页；动画完成后无感地重置真实内容位置。
    ///
    /// - Parameters:
    ///   - index: 目标页码。
    ///   - dragOffset: 当前手势拖动偏移量。
    ///   - animated: 是否使用归位动画。
    ///   - previousIndex: 动画前页码，用于判断首尾循环方向。
    ///   - previousOffset: 动画前偏移量，用于判断循环翻页方向。
    func setPage(
        index: Int,
        dragOffset: CGFloat,
        animated: Bool,
        previousIndex: Int? = nil,
        previousOffset: CGFloat = 0
    ) {
        settleGeneration += 1
        let generation = settleGeneration
        let realTargetX = -CGFloat(index + 1) * bounds.width + dragOffset
        var targetX = realTargetX
        var shouldRecenterAfterAnimation = false

        if animated, renderedPageCount > 1, let previousIndex {
            let lastIndex = renderedPageCount - 1
            if previousIndex == 0, index == lastIndex, previousOffset > 0 {
                targetX = 0
                shouldRecenterAfterAnimation = true
            } else if previousIndex == lastIndex, index == 0, previousOffset < 0 {
                targetX = -CGFloat(renderedPageCount + 1) * bounds.width
                shouldRecenterAfterAnimation = true
            }
        }

        let origin = NSPoint(x: targetX, y: 0)
        let recenterAfterAnimation = shouldRecenterAfterAnimation
        let recenterOrigin = NSPoint(x: realTargetX, y: 0)
        if animated {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let animationDuration: TimeInterval = reduceMotion ? 0.14 : 0.38
            let timing = reduceMotion
                ? CAMediaTimingFunction(name: .easeOut)
                : CAMediaTimingFunction(controlPoints: 0.20, 0.72, 0.24, 1.0)
            LumaEventLog.shared.writeInteraction(
                .page,
                "pager.setPage",
                fields: [
                    "pageIndex": index,
                    "dragOffset": String(format: "%.1f", dragOffset),
                    "animated": animated,
                    "contentOriginX": String(format: "%.1f", origin.x)
                ]
            )
            suspendInteraction(for: reduceMotion ? 0.16 : 0.40)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                context.timingFunction = timing
                contentView.animator().setFrameOrigin(origin)
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, self.settleGeneration == generation else {
                        return
                    }
                    if recenterAfterAnimation {
                        self.contentView.setFrameOrigin(recenterOrigin)
                    }
                }
            }
        } else {
            interactionSuspensionGeneration += 1
            isInteractionSuspended = false
            if interactionLogThrottle.shouldLog("pager.setPage.immediate", interval: 0.10) {
                LumaEventLog.shared.writeInteraction(
                    .page,
                    "pager.setPage",
                    fields: [
                        "pageIndex": index,
                        "dragOffset": String(format: "%.1f", dragOffset),
                        "animated": animated,
                        "contentOriginX": String(format: "%.1f", origin.x)
                    ]
                )
            }
            contentView.setFrameOrigin(origin)
        }
    }

    private func frameForTile(at index: Int) -> NSRect {
        let localIndex = index % metrics.itemsPerPage
        let row = localIndex / metrics.columns
        let column = localIndex % metrics.columns
        return NSRect(
            x: horizontalContentInset
                + metrics.leadingInset
                + CGFloat(column) * (metrics.tileWidth + metrics.columnSpacing),
            y: CGFloat(row) * (metrics.tileHeight + metrics.rowSpacing),
            width: metrics.tileWidth,
            height: metrics.tileHeight
        )
    }

    private var backingScaleFactor: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    /// 渲染首尾轻量副本页，用于连续循环翻页。
    private func refreshEdgeReplicas() {
        let start = CACurrentMediaTime()
        guard renderedPageCount > 1 else {
            leadingReplica.clear()
            trailingReplica.clear()
            leadingReplica.isHidden = true
            trailingReplica.isHidden = true
            LumaEventLog.shared.writeInteraction(
                .performance,
                "pager.refreshEdgeReplicaPages",
                fields: [
                    "pages": renderedPageCount,
                    "leadingItems": 0,
                    "trailingItems": 0,
                    "durationMS": Int((CACurrentMediaTime() - start) * 1_000)
                ]
            )
            return
        }

        leadingReplica.isHidden = false
        trailingReplica.isHidden = false

        leadingReplica.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        trailingReplica.frame = NSRect(
            x: CGFloat(renderedPageCount + 1) * bounds.width,
            y: 0,
            width: bounds.width,
            height: bounds.height
        )

        let lastPageItems = replicaItems(for: renderedPageCount - 1)
        let firstPageItems = replicaItems(for: 0)

        leadingReplica.render(
            items: lastPageItems,
            store: store,
            metrics: metrics
        )

        trailingReplica.render(
            items: firstPageItems,
            store: store,
            metrics: metrics
        )

        LumaEventLog.shared.writeInteraction(
            .performance,
            "pager.refreshEdgeReplicaPages",
            fields: [
                "pages": renderedPageCount,
                "leadingItems": lastPageItems.count,
                "trailingItems": firstPageItems.count,
                "durationMS": Int((CACurrentMediaTime() - start) * 1_000)
            ]
        )
    }

    private func replicaItems(for pageIndex: Int) -> [(tile: LauncherTile, frame: NSRect)] {
        let tiles = store.visibleTiles
        guard metrics.itemsPerPage > 0 else {
            return []
        }

        let startIndex = pageIndex * metrics.itemsPerPage
        guard startIndex < tiles.count else {
            return []
        }

        let endIndex = min(startIndex + metrics.itemsPerPage, tiles.count)

        return (startIndex..<endIndex).map { index in
            (tile: tiles[index], frame: frameForTile(at: index))
        }
    }

    private func tile(atDraggingLocation location: NSPoint) -> LauncherTileView? {
        let rawLocalPoint = convert(location, from: nil)
        let flippedLocalPoint = NSPoint(
            x: rawLocalPoint.x,
            y: bounds.height - rawLocalPoint.y
        )
        let rawHit = hitTestTile(at: rawLocalPoint, from: self, useDragTarget: true)
        let flippedHit = hitTestTile(at: flippedLocalPoint, from: self, useDragTarget: true)

        if interactionLogThrottle.shouldLog("pager.drag.locationCompare", interval: 0.10) {
            LumaEventLog.shared.writeInteraction(
                .drag,
                "pager.drag.locationCompare",
                fields: [
                    "rawLocal": lumaLogPoint(rawLocalPoint),
                    "flippedLocal": lumaLogPoint(flippedLocalPoint),
                    "rawHit": rawHit?.tileID ?? "nil",
                    "flippedHit": flippedHit?.tileID ?? "nil"
                ]
            )
        }

        guard let tileView = flippedHit ?? rawHit,
              activeTileIDs.contains(tileView.tileID),
              tileView.alphaValue > 0.05 else {
            return nil
        }
        return tileView
    }

    private func hitTestTile(
        at point: NSPoint,
        from sourceView: NSView,
        useDragTarget: Bool = false
    ) -> LauncherTileView? {
        guard let currentPage = pageViews[store.pageIndex] else {
            LumaEventLog.shared.writeInteraction(.hitTest, "pager.tileHit.miss", fields: ["reason": "missingPage"])
            return nil
        }

        let pagerPoint: NSPoint
        if sourceView === self {
            pagerPoint = point
        } else {
            pagerPoint = convert(point, from: sourceView)
        }
        guard currentPage.bounds.contains(pagerPoint) else {
            if interactionLogThrottle.shouldLog("pager.tileHit.outside", interval: 0.12) {
                LumaEventLog.shared.writeInteraction(
                    .hitTest,
                    "pager.tileHit.miss",
                    fields: [
                        "reason": "outsidePage",
                        "pagerPoint": lumaLogPoint(pagerPoint),
                        "pageIndex": store.pageIndex
                    ]
                )
            }
            return nil
        }

        let tileView = currentPage.subviews
            .compactMap { $0 as? LauncherTileView }
            .reversed()
            .first { view in
                guard view.frame.contains(pagerPoint) else {
                    return false
                }
                let localPoint = NSPoint(
                    x: pagerPoint.x - view.frame.minX,
                    y: pagerPoint.y - view.frame.minY
                )
                return useDragTarget
                    ? view.containsDragTargetPoint(localPoint)
                    : view.containsInteractivePoint(localPoint)
            }
        if let tileView {
            if interactionLogThrottle.shouldLog("pager.tileHit.hit.\(tileView.tileID)", interval: 0.30) {
                LumaEventLog.shared.writeInteraction(
                    .hitTest,
                    "pager.tileHit.hit",
                    fields: [
                        "tileID": tileView.tileID,
                        "pagerPoint": lumaLogPoint(pagerPoint),
                        "tileFrame": lumaLogRect(tileView.frame),
                        "pageIndex": store.pageIndex
                    ]
                )
            }
        }
        return tileView
    }

    func applyDragPreview() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let start = CACurrentMediaTime()

        let tiles = store.visibleTiles
        var movements: [(view: LauncherTileView, frame: NSRect)] = []

        for (index, tile) in tiles.enumerated() {
            guard let view = tileViews[tile.id] else {
                continue
            }

            let pageIndex = index / metrics.itemsPerPage
            guard let pageView = pageViews[pageIndex] else {
                continue
            }

            let targetFrame = frameForTile(at: index)

            if view.superview !== pageView {
                let currentFrameInWindow = view.convert(view.bounds, to: nil)
                pageView.addSubview(view)
                view.frame = pageView.convert(currentFrameInWindow, from: nil)
            }

            if view.tileID == store.draggedTileID {
                view.frame = targetFrame
                continue
            }

            if view.frame.integral != targetFrame.integral {
                movements.append((view, targetFrame))
            }
        }

        guard !movements.isEmpty else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.11
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.18,
                0.82,
                0.22,
                1.0
            )

            for movement in movements {
                movement.view.animator().frame = movement.frame
            }
        }
        LumaEventLog.shared.writeInteraction(
            .performance,
            "pager.applyDragPreview",
            fields: [
                "movements": movements.count,
                "dragID": store.currentDragID ?? "nil",
                "durationMS": Int((CACurrentMediaTime() - start) * 1_000)
            ]
        )
    }

    func debugTileView(withID tileID: String) -> LauncherTileView? {
        tileViews[tileID]
    }

    /// 悬停目标变化时，只发送一次内存排序预览。
    ///
    /// - Parameters:
    ///   - draggedID: 被拖拽 Tile 标识。
    ///   - target: 当前 Hover 的目标 Tile 视图。
    private func updateDropTarget(draggedID: String, target: LauncherTileView) {
        guard target.tileID != draggedID else {
            dropTargetID = nil
            isFolderDropTarget = false
            return
        }

        if dropTargetID != target.tileID || isFolderDropTarget {
            dropTargetID = target.tileID
            isFolderDropTarget = false
            LumaEventLog.shared.writeInteraction(
                .drag,
                "drag.targetChanged",
                fields: [
                    "dragID": store.currentDragID ?? "nil",
                    "draggedID": draggedID,
                    "targetID": target.tileID
                ]
            )
            store.previewMoveTile(draggedID, before: target.tileID)
        }
    }

    private func updateFolderDropTarget(draggedID: String, target: LauncherTileView) {
        guard target.tileID != draggedID else {
            dropTargetID = nil
            isFolderDropTarget = false
            return
        }

        guard dropTargetID != target.tileID || !isFolderDropTarget else {
            return
        }

        dropTargetID = target.tileID
        isFolderDropTarget = true
        LumaEventLog.shared.writeInteraction(
            .drag,
            "drag.folderTargetChanged",
            fields: [
                "dragID": store.currentDragID ?? "nil",
                "draggedID": draggedID,
                "targetID": target.tileID
            ]
        )
    }

    private func updateEdgePagingIfNeeded(windowLocation: NSPoint) {
        lastDragWindowLocation = windowLocation

        guard store.currentDragID != nil,
              store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              store.pageCount > 1,
              bounds.width > 0 else {
            cancelEdgePaging()
            return
        }

        let localPoint = convert(windowLocation, from: nil)
        let edgeWidth = min(140, max(96, bounds.width * 0.08))

        let direction: Int
        if localPoint.x <= edgeWidth {
            direction = -1
        } else if localPoint.x >= bounds.width - edgeWidth {
            direction = 1
        } else {
            cancelEdgePaging()
            return
        }

        scheduleEdgePaging(direction: direction)
    }

    private func scheduleEdgePaging(direction: Int) {
        guard direction != 0 else {
            cancelEdgePaging()
            return
        }

        if edgePageDirection == direction, edgePageWorkItem != nil {
            return
        }

        cancelEdgePaging()
        edgePageDirection = direction

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let direction = self.edgePageDirection
            self.edgePageWorkItem = nil

            guard direction != 0,
                  self.store.currentDragID != nil,
                  self.store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  self.store.pageCount > 1 else {
                self.cancelEdgePaging()
                return
            }

            self.dropTargetID = nil
            self.isFolderDropTarget = false
            LumaEventLog.shared.writeInteraction(
                .drag,
                "drag.edgePage",
                fields: [
                    "dragID": self.store.currentDragID ?? "nil",
                    "direction": direction,
                    "pageIndex": self.store.pageIndex
                ]
            )

            self.store.changePage(by: direction)

            if let lastLocation = self.lastDragWindowLocation {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                    self?.updateEdgePagingIfNeeded(windowLocation: lastLocation)
                }
            }
        }

        edgePageWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func cancelEdgePaging() {
        edgePageWorkItem?.cancel()
        edgePageWorkItem = nil
        edgePageDirection = 0
        lastDragWindowLocation = nil
    }

    private func currentDragWindowLocation(from view: NSView) -> NSPoint? {
        guard let window = view.window else {
            return nil
        }
        return window.convertPoint(fromScreen: NSEvent.mouseLocation)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let draggedID = sender.draggingPasteboard.string(forType: .string) else {
            cancelEdgePaging()
            return .move
        }

        updateEdgePagingIfNeeded(windowLocation: sender.draggingLocation)

        guard store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let target = tile(atDraggingLocation: sender.draggingLocation),
              target.tileID != draggedID else {
            if !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cancelEdgePaging()
            }
            return .move
        }

        if interactionLogThrottle.shouldLog("pager.draggingUpdated", interval: 0.10) {
            LumaEventLog.shared.writeInteraction(
                .drag,
                "pager.draggingUpdated",
                fields: [
                    "dragID": store.currentDragID ?? "nil",
                    "draggedID": draggedID,
                    "targetID": target.tileID
                ]
            )
        }
        if shouldCreateFolder(from: draggedID, onto: target, at: sender.draggingLocation) {
            updateFolderDropTarget(draggedID: draggedID, target: target)
            return .move
        }
        updateDropTarget(draggedID: draggedID, target: target)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropTargetID = nil
        isFolderDropTarget = false
        cancelEdgePaging()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        var didCommitDrop = false
        defer {
            currentDragCommitted = didCommitDrop
            dropTargetID = nil
            isFolderDropTarget = false
            cancelEdgePaging()
        }

        guard store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let draggedID = sender.draggingPasteboard.string(forType: .string),
              let target = tile(atDraggingLocation: sender.draggingLocation),
              target.tileID != draggedID else {
            return false
        }

        LumaEventLog.shared.writeInteraction(
            .drag,
            "pager.performDrop",
            fields: [
                "dragID": store.currentDragID ?? "nil",
                "draggedID": draggedID,
                "targetID": target.tileID
            ]
        )
        if let folder = target.tile.folder, draggedID.hasPrefix("app:") {
            store.addApp(draggedID, to: folder.id)
        } else if shouldCreateFolder(from: draggedID, onto: target, at: sender.draggingLocation) {
            store.createFolder(containingAppIDs: [draggedID, target.tileID])
        } else {
            updateDropTarget(draggedID: draggedID, target: target)
        }
        didCommitDrop = true
        return true
    }
}

extension LauncherPagerView: LauncherTileViewDelegate {
    func tileView(_ view: LauncherTileView, didRequestOpen tile: LauncherTile) {
        LumaEventLog.shared.writeInteraction(
            .tile,
            "tile.open.forward",
            fields: [
                "tileID": tile.id,
                "kind": tile.app == nil ? "folder" : "app"
            ]
        )
        delegate?.pager(self, open: tile)
    }

    func tileViewDidRequestEditing(_ view: LauncherTileView) {
        delegate?.pagerDidRequestEditing(self)
    }

    func tileViewDidBeginDragging(_ view: LauncherTileView) {
        currentDragCommitted = false
        setPageRasterizationEnabled(false)
        let commitPolicy: DragCommitPolicy = store.isInManualEditMode ? .manualCommit : .autoCommit
        LumaEventLog.shared.writeInteraction(
            .drag,
            "tile.drag.begin",
            fields: [
                "tileID": view.tileID,
                "commitPolicy": commitPolicy.rawValue
            ]
        )
        store.beginDraggingTile(view.tileID, commitPolicy: commitPolicy)
    }

    func tileViewDidEndDragging(_ view: LauncherTileView, operation: NSDragOperation) {
        dropTargetID = nil
        isFolderDropTarget = false
        cancelEdgePaging()
        let dragID = store.currentDragID
        let hasPendingDragPreview = store.hasPendingDragPreview
        let shouldCommit =
            currentDragCommitted
            || hasPendingDragPreview
        LumaEventLog.shared.writeInteraction(
            .drag,
            "tile.drag.end",
            fields: [
                "tileID": view.tileID,
                "dragID": dragID ?? "nil",
                "committed": shouldCommit,
                "operation": operation.rawValue,
                "currentDragCommitted": currentDragCommitted,
                "hasPendingDragPreview": hasPendingDragPreview,
                "replicaRefresh": shouldCommit ? "scheduled" : "skipped"
            ]
        )
        store.endDraggingTile(commit: shouldCommit)
        currentDragCommitted = false
        setPageRasterizationEnabled(true)
        if shouldCommit {
            scheduleEdgeReplicaRefresh(after: 0.25)
        }
    }

    func tileView(_ view: LauncherTileView, draggingUpdatedWith draggedID: String) -> NSDragOperation {
        guard let windowLocation = currentDragWindowLocation(from: view) else {
            cancelEdgePaging()
            return []
        }

        updateEdgePagingIfNeeded(windowLocation: windowLocation)

        guard store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cancelEdgePaging()
            return []
        }

        if shouldCreateFolder(from: draggedID, onto: view, at: windowLocation) {
            updateFolderDropTarget(draggedID: draggedID, target: view)
            return .move
        }
        updateDropTarget(draggedID: draggedID, target: view)
        return .move
    }

    func tileView(_ view: LauncherTileView, performDropWith draggedID: String, at windowLocation: NSPoint) -> Bool {
        var didCommitDrop = false
        defer {
            currentDragCommitted = didCommitDrop
            dropTargetID = nil
            isFolderDropTarget = false
            cancelEdgePaging()
        }

        guard store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draggedID != view.tileID else {
            return false
        }

        LumaEventLog.shared.writeInteraction(
            .drag,
            "tile.performDrop",
            fields: [
                "dragID": store.currentDragID ?? "nil",
                "draggedID": draggedID,
                "targetID": view.tileID
            ]
        )
        if let folder = view.tile.folder, draggedID.hasPrefix("app:") {
            store.addApp(draggedID, to: folder.id)
        } else if shouldCreateFolder(from: draggedID, onto: view, at: windowLocation) {
            store.createFolder(containingAppIDs: [draggedID, view.tileID])
        } else {
            updateDropTarget(draggedID: draggedID, target: view)
        }
        didCommitDrop = true
        return true
    }

    private func shouldCreateFolder(
        from draggedID: String,
        onto target: LauncherTileView,
        at windowLocation: NSPoint
    ) -> Bool {
        guard draggedID.hasPrefix("app:"),
              target.tile.app != nil,
              draggedID != target.tileID else {
            return false
        }
        return target.wantsCreateFolderDrop(atWindowLocation: windowLocation)
    }

    func tileView(_ view: LauncherTileView, contextMenuFor tile: LauncherTile) -> NSMenu {
        delegate?.pager(self, contextMenuFor: tile) ?? NSMenu()
    }
}
