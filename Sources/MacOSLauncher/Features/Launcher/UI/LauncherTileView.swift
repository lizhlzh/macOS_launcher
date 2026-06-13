import AppKit
import QuartzCore

/// 展示并处理单个应用或文件夹 Tile 的交互。
///
/// 输入方向：
/// 鼠标/拖拽/菜单事件 -> Tile delegate -> Pager/Root -> `LauncherStore`。
@MainActor
final class LauncherTileView: NSView, NSDraggingSource {
    weak var delegate: LauncherTileViewDelegate?

    private(set) var tile: LauncherTile
    var tileID: String { tile.id }

    private let store: LauncherStore
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var metrics: LauncherGridMetrics
    private var showJiggle = false
    private var isDraggingTile = false
    private var isHovering = false
    private var trackingAreaToken: NSTrackingArea?
    private var mouseDownEvent: NSEvent?
    private var longPressTriggered = false
    private var pressedTile: LauncherTile?
    private var renderedTile: LauncherTile?
    private var renderedIconSize: CGFloat = 0
    private var isHiddenApp = false
    private let interactionLogThrottle = InteractionLogThrottle()
    private let wiggleAnimationKey = "luma.tile.wiggle"

    override var isFlipped: Bool { true }

    private var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 创建 Tile 视图。
    ///
    /// - Parameters:
    ///   - tile: 当前展示的应用或文件夹模型。
    ///   - store: 提供图标和隐藏状态的业务 Store。
    ///   - metrics: 当前网格布局计算结果。
    ///   - showJiggle: 创建时是否处于手动整理抖动状态。
    init(
        tile: LauncherTile,
        store: LauncherStore,
        metrics: LauncherGridMetrics,
        showJiggle: Bool
    ) {
        self.tile = tile
        self.store = store
        self.metrics = metrics
        self.showJiggle = showJiggle
        super.init(frame: .zero)

        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tile.title)
        layer?.drawsAsynchronously = true
        layer?.shouldRasterize = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        LauncherTileVisualStyle.configureIconLayer(iconView.layer)
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.wraps = true
        titleLabel.cell?.usesSingleLineMode = false
        titleLabel.wantsLayer = true
        LauncherTileVisualStyle.configureTitleLayer(titleLabel.layer)
        addSubview(titleLabel)

        registerForDraggedTypes([.string])
        update(tile: tile, metrics: metrics, showJiggle: showJiggle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.rasterizationScale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
    }

    override func layout() {
        super.layout()
        let iconX = floor((bounds.width - metrics.iconSize) / 2)
        let iconY = metrics.tileVerticalPadding
        iconView.frame = NSRect(x: iconX, y: iconY, width: metrics.iconSize, height: metrics.iconSize)
        titleLabel.frame = NSRect(
            x: 2,
            y: iconView.frame.maxY + metrics.iconTitleSpacing,
            width: bounds.width - 4,
            height: metrics.titleHeight
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaToken {
            removeTrackingArea(trackingAreaToken)
        }
        let tracking = NSTrackingArea(
            rect: iconView.frame,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(tracking)
        trackingAreaToken = tracking
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        containsClickPoint(point) ? self : nil
    }

    func containsClickPoint(_ point: NSPoint) -> Bool {
        let iconRect = iconView.frame.insetBy(dx: -6, dy: -6)
        let titleRect = titleLabel.frame.insetBy(dx: -4, dy: -3)
        return iconRect.contains(point) || titleRect.contains(point)
    }

    func containsDragTargetPoint(_ point: NSPoint) -> Bool {
        let iconRect = iconView.frame.insetBy(dx: -18, dy: -16)
        let titleRect = titleLabel.frame.insetBy(dx: -10, dy: -8)
        return iconRect.contains(point) || titleRect.contains(point)
    }

    func containsFolderDropPoint(_ point: NSPoint) -> Bool {
        let inset = max(14, min(iconView.frame.width, iconView.frame.height) * 0.24)
        return iconView.frame.insetBy(dx: inset, dy: inset).contains(point)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        pressedTile = tile
        longPressTriggered = false
        LumaEventLog.shared.writeInteraction(
            .tile,
            "tile.mouseDown",
            fields: [
                "tileID": tile.id,
                "showJiggle": showJiggle,
                "point": lumaLogPoint(convert(event.locationInWindow, from: nil))
            ]
        )
    }

    /// 达到移动距离和长按阈值后启动原生拖拽。
    ///
    /// - Parameter event: 当前鼠标拖动事件。
    override func mouseDragged(with event: NSEvent) {
        guard !isDraggingTile, let initialEvent = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - initialEvent.locationInWindow.x
        let dy = event.locationInWindow.y - initialEvent.locationInWindow.y
        guard hypot(dx, dy) > 4 else { return }

        if !showJiggle {
            guard event.timestamp - initialEvent.timestamp >= 0.32 else {
                return
            }
            longPressTriggered = true
        }

        isDraggingTile = true
        LumaEventLog.shared.writeInteraction(
            .drag,
            "tile.mouseDragged.beginSession",
            fields: [
                "tileID": tile.id,
                "distance": String(format: "%.1f", hypot(dx, dy))
            ]
        )
        delegate?.tileViewDidBeginDragging(self)

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(tile.id, forType: .string)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let previewImage = dragPreviewImage() ?? iconView.image
        draggingItem.setDraggingFrame(iconView.frame, contents: previewImage)
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
        updateAppearance(animated: true)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownEvent = nil
            pressedTile = nil
        }

        guard !isDraggingTile, !longPressTriggered, !showJiggle else { return }
        guard let pressedTile, pressedTile.id == tile.id else { return }
        LumaEventLog.shared.writeInteraction(
            .tile,
            "tile.mouseUp.open",
            fields: [
                "tileID": pressedTile.id,
                "point": lumaLogPoint(convert(event.locationInWindow, from: nil))
            ]
        )
        delegate?.tileView(self, didRequestOpen: pressedTile)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        delegate?.tileView(self, contextMenuFor: tile)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.string(forType: .string) != nil else {
            return []
        }
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let draggedID = sender.draggingPasteboard.string(forType: .string) else {
            return []
        }
        if interactionLogThrottle.shouldLog("tile.draggingUpdated.\(tile.id)", interval: 0.10) {
            LumaEventLog.shared.writeInteraction(
                .drag,
                "tile.draggingUpdated",
                fields: [
                    "draggedID": draggedID,
                    "targetID": tile.id
                ]
            )
        }
        return delegate?.tileView(self, draggingUpdatedWith: draggedID) ?? []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.string(forType: .string) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let draggedID = sender.draggingPasteboard.string(forType: .string) else {
            return false
        }
        LumaEventLog.shared.writeInteraction(
            .drag,
            "tile.performDragOperation",
            fields: [
                "draggedID": draggedID,
                "targetID": tile.id
            ]
        )
        return delegate?.tileView(self, performDropWith: draggedID, at: sender.draggingLocation) ?? false
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDraggingTile = false
        mouseDownEvent = nil
        updateAppearance(animated: false)
        LumaEventLog.shared.writeInteraction(
            .drag,
            "tile.draggingSessionEnded",
            fields: [
                "tileID": tile.id,
                "screenPoint": lumaLogPoint(screenPoint),
                "operation": operation.rawValue
            ]
        )
        delegate?.tileViewDidEndDragging(self, operation: operation)
    }

    /// 复用视图，只更新发生变化的模型、图标、布局和编辑状态。
    ///
    /// - Parameters:
    ///   - tile: 最新 Tile 模型。
    ///   - metrics: 最新网格布局计算结果。
    ///   - showJiggle: 当前是否显示手动整理抖动。
    func update(tile: LauncherTile, metrics: LauncherGridMetrics, showJiggle: Bool) {
        let wasUnrendered = renderedTile == nil
        let tileChanged = renderedTile != tile
        let iconSizeChanged = abs(renderedIconSize - metrics.iconSize) > 0.5
        let isFolder: Bool
        if case .folder = tile.kind {
            isFolder = true
        } else {
            isFolder = false
        }
        let needsNewIcon = tileChanged || (isFolder && iconSizeChanged)
        let metricsChanged = iconSizeChanged
            || abs(self.metrics.tileWidth - metrics.tileWidth) > 0.5
            || abs(self.metrics.tileHeight - metrics.tileHeight) > 0.5
            || abs(self.metrics.titleHeight - metrics.titleHeight) > 0.5
        let jiggleChanged = self.showJiggle != showJiggle
        let hiddenState = tile.app.map { store.isAppHidden($0.id) } ?? false

        self.tile = tile
        setAccessibilityLabel(tile.title)
        if tile.folder != nil {
            setAccessibilityHelp(L10n.text(.folderAccessibilityHelp))
        } else {
            setAccessibilityHelp(L10n.text(.applicationAccessibilityHelp))
        }
        self.metrics = metrics
        self.showJiggle = showJiggle
        isHiddenApp = hiddenState
        if titleLabel.stringValue != tile.title {
            titleLabel.stringValue = tile.title
        }
        if needsNewIcon {
            iconView.image = image(for: tile)
        }
        renderedTile = tile
        renderedIconSize = metrics.iconSize

        if jiggleChanged {
            updateJiggleAnimation()
        }
        if metricsChanged {
            needsLayout = true
        }
        if wasUnrendered {
            updateAppearance(animated: false)
        }
    }

    func setEditing(_ showJiggle: Bool, dragged: Bool) {
        self.showJiggle = showJiggle
        isDraggingTile = dragged
        updateJiggleAnimation()
        updateAppearance(animated: true)
    }

    func wantsCreateFolderDrop(atWindowLocation location: NSPoint) -> Bool {
        let localPoint = convert(location, from: nil)
        return containsFolderDropPoint(localPoint)
    }

    private func image(for tile: LauncherTile) -> NSImage? {
        switch tile.kind {
        case let .app(app):
            store.appIcon(for: app, size: metrics.iconSize)
        case let .folder(_, apps):
            FolderIconRenderer.image(
                apps: apps,
                store: store,
                size: metrics.iconSize
            )
        }
    }

    private func dragPreviewImage() -> NSImage? {
        let sourceBounds = iconView.bounds
        guard sourceBounds.width > 0,
              sourceBounds.height > 0,
              let representation = iconView.bitmapImageRepForCachingDisplay(in: sourceBounds) else {
            return iconView.image
        }

        iconView.cacheDisplay(in: sourceBounds, to: representation)

        let image = NSImage(size: sourceBounds.size)
        image.addRepresentation(representation)
        return image
    }

    /// 应用 Hover、隐藏和拖拽视觉状态，不修改 Tile 业务数据。
    ///
    /// - Parameter animated: 是否执行现有外观过渡动画。
    private func updateAppearance(animated: Bool) {
        let visibilityAlpha: CGFloat = isHiddenApp ? 0.62 : 1
        let targetAlpha: CGFloat = (isDraggingTile ? 0.42 : 1) * visibilityAlpha
        let hoverActive = isHovering && !isDraggingTile
        let targetScale: CGFloat = shouldReduceMotion ? 1 : (hoverActive ? 1.016 : 1)
        let targetTranslationY: CGFloat = shouldReduceMotion ? 0 : (hoverActive ? -1 : 0)
        var targetTransform = CATransform3DIdentity
        targetTransform = CATransform3DTranslate(targetTransform, 0, targetTranslationY, 0)
        targetTransform = CATransform3DScale(targetTransform, targetScale, targetScale, 1)
        let targetShadowOpacity: Float = hoverActive ? 0.32 : LauncherTileVisualStyle.iconShadowOpacity
        let targetShadowRadius: CGFloat = hoverActive ? 13 : LauncherTileVisualStyle.iconShadowRadius
        let targetShadowOffset = hoverActive
            ? CGSize(width: 0, height: -7)
            : LauncherTileVisualStyle.iconShadowOffset
        titleLabel.textColor = NSColor.white.withAlphaComponent(isHiddenApp ? 0.76 : 1)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.72, 0.24, 1.0)
                iconView.animator().alphaValue = targetAlpha
                titleLabel.animator().alphaValue = visibilityAlpha
            }

            if let layer = iconView.layer {
                let animation = CABasicAnimation(keyPath: "transform")
                animation.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
                animation.toValue = NSValue(caTransform3D: targetTransform)
                animation.duration = 0.14
                animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.72, 0.24, 1.0)
                layer.transform = targetTransform
                layer.add(animation, forKey: "hoverScale")

                let shadowOpacity = CABasicAnimation(keyPath: "shadowOpacity")
                shadowOpacity.fromValue = layer.presentation()?.shadowOpacity ?? layer.shadowOpacity
                shadowOpacity.toValue = targetShadowOpacity
                shadowOpacity.duration = 0.14
                shadowOpacity.timingFunction = animation.timingFunction
                layer.shadowOpacity = targetShadowOpacity
                layer.add(shadowOpacity, forKey: "hoverShadowOpacity")

                let shadowRadius = CABasicAnimation(keyPath: "shadowRadius")
                shadowRadius.fromValue = layer.presentation()?.shadowRadius ?? layer.shadowRadius
                shadowRadius.toValue = targetShadowRadius
                shadowRadius.duration = 0.14
                shadowRadius.timingFunction = animation.timingFunction
                layer.shadowRadius = targetShadowRadius
                layer.add(shadowRadius, forKey: "hoverShadowRadius")
                layer.shadowOffset = targetShadowOffset
            }
        } else {
            iconView.alphaValue = targetAlpha
            titleLabel.alphaValue = visibilityAlpha
            iconView.layer?.transform = targetTransform
            iconView.layer?.shadowOpacity = targetShadowOpacity
            iconView.layer?.shadowRadius = targetShadowRadius
            iconView.layer?.shadowOffset = targetShadowOffset
        }
    }

    private func updateJiggleAnimation() {
        guard !shouldReduceMotion else {
            removeJiggleAnimation()
            return
        }

        if showJiggle, !isDraggingTile {
            applyJiggleAnimationIfNeeded()
        } else {
            removeJiggleAnimation()
        }
    }

    private func applyJiggleAnimationIfNeeded() {
        let phaseSeed = Double(abs(tile.id.hashValue % 11)) * 0.03
        for view in [iconView, titleLabel] {
            view.wantsLayer = true
            guard let layer = view.layer,
                  layer.animation(forKey: wiggleAnimationKey) == nil else {
                continue
            }

            let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            animation.values = [-0.026, 0.022, -0.020, 0.025]
            animation.keyTimes = [0, 0.33, 0.66, 1]
            animation.duration = 0.18 + phaseSeed
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.isAdditive = true
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: wiggleAnimationKey)
        }
    }

    private func removeJiggleAnimation() {
        iconView.layer?.removeAnimation(forKey: wiggleAnimationKey)
        titleLabel.layer?.removeAnimation(forKey: wiggleAnimationKey)
    }
}
