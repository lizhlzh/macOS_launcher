import AppKit
import QuartzCore

/// 组合启动器背景、顶部栏、分页区、状态提示和文件夹浮层。
///
/// 数据方向：
/// `LauncherStore.onChange` -> `LauncherRootView` -> Pager/Header/状态区重绘。
/// 用户操作方向：
/// 控件和 delegate 回调 -> `LauncherStore` 或 Controller 闭包。
@MainActor
final class LauncherRootView: NSView, NSTextFieldDelegate {
    private let rootPresentationAnimationKey = "luma.root.presentation"
    private let store: LauncherStore
    private let onClose: (String) -> Void
    private let onEscape: () -> Void

    private let effectView = NSVisualEffectView()
    private let tintView = GradientBackgroundView()
    private let headerView = NSVisualEffectView()
    private let searchIconView = NSImageView()
    private let searchField = SearchTextField()
    private let sortButton = HeaderButton()
    private let layoutButton = HeaderButton()
    private let filterButton = HeaderButton()
    private let editButton = HeaderButton()
    private let folderButton = HeaderButton()
    private let rescanButton = HeaderButton()
    private let closeButton = HeaderButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let pager: LauncherPagerView
    private let pageDots = PageDotsView()

    private var folderOverlay: FolderOverlayView?
    private let interactionLogThrottle = InteractionLogThrottle()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// 创建启动器根视图。
    ///
    /// - Parameters:
    ///   - frame: 根视图初始尺寸。
    ///   - store: 启动器业务状态。
    ///   - onClose: 用户请求关闭启动器时执行的闭包。
    ///   - onEscape: 用户按 Escape 时执行的闭包。
    init(frame: NSRect, store: LauncherStore, onClose: @escaping (String) -> Void, onEscape: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        self.onEscape = onEscape
        pager = LauncherPagerView(store: store)
        super.init(frame: frame)

        wantsLayer = true
        configureBackground()
        configureHeader()
        configurePager()
        configureStatusLabel()
        addSubview(headerView, positioned: .above, relativeTo: pager)

        store.onChange = { [weak self] change in
            self?.handleStoreChange(change)
        }
        pager.delegate = self
        reload(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 布局稳定的顶层区域；子视图负责各自内部布局。
    override func layout() {
        super.layout()

        effectView.frame = bounds
        tintView.frame = bounds

        let top = safeTopPadding()
        let horizontalMargin: CGFloat = 48
        let headerAvailableWidth = max(320, bounds.width - horizontalMargin * 2)
        let headerMaxWidth = min(1450, headerAvailableWidth)
        let buttonHeight: CGFloat = 50
        let sortWidth = max(L10n.isChinese ? 148 : 132, sortButton.preferredContentWidth)
        let layoutWidth = max(108, layoutButton.preferredContentWidth)
        let controlWidths: [CGFloat] = [
            sortWidth,
            layoutWidth,
            58, 58, 58, 58, 58
        ]
        let controlSpacing: CGFloat = 7
        let controlsWidth = controlWidths.reduce(0, +)
            + CGFloat(controlWidths.count - 1) * controlSpacing
        let sidePadding: CGFloat = 18
        let searchToControlsSpacing: CGFloat = 10
        let minimumSearchWidth: CGFloat = 220
        let idealSearchWidth: CGFloat = 420
        let minimumHeaderWidth = sidePadding
            + minimumSearchWidth
            + searchToControlsSpacing
            + controlsWidth
            + sidePadding
        let idealHeaderWidth = sidePadding
            + idealSearchWidth
            + searchToControlsSpacing
            + controlsWidth
            + sidePadding
        let headerWidth = min(
            headerMaxWidth,
            max(minimumHeaderWidth, min(idealHeaderWidth, headerAvailableWidth))
        )
        headerView.frame = NSRect(
            x: floor((bounds.width - headerWidth) / 2),
            y: top,
            width: headerWidth,
            height: 66
        )

        let minimumVisibleSearchWidth: CGFloat = headerWidth < minimumHeaderWidth ? 160 : minimumSearchWidth
        let searchAreaWidth = max(
            minimumVisibleSearchWidth,
            headerWidth - sidePadding - controlsWidth - searchToControlsSpacing - sidePadding
        )
        let searchCenterY = headerView.bounds.midY
        searchField.frame = NSRect(
            x: sidePadding,
            y: 8,
            width: searchAreaWidth,
            height: buttonHeight
        )
        searchIconView.frame = NSRect(
            x: searchField.frame.minX + 10,
            y: floor(searchCenterY - 9),
            width: 18,
            height: 18
        )

        var x = sidePadding + searchAreaWidth + searchToControlsSpacing
        for (button, width) in zip(
            [sortButton, layoutButton, filterButton, editButton, folderButton, rescanButton, closeButton],
            controlWidths
        ) {
            button.frame = NSRect(x: x, y: 8, width: width, height: buttonHeight)
            x += width + controlSpacing
        }

        let pagerTop = headerView.frame.maxY + 36
        let pagerBottom: CGFloat = 74
        pager.frame = NSRect(
            x: 0,
            y: pagerTop,
            width: max(320, bounds.width),
            height: max(260, bounds.height - pagerTop - pagerBottom)
        )
        pageDots.frame = NSRect(x: 48, y: bounds.height - 54, width: max(320, bounds.width - 96), height: 24)
        statusLabel.frame = NSRect(
            x: floor((bounds.width - 560) / 2),
            y: headerView.frame.maxY + 8,
            width: 560,
            height: 22
        )
        folderOverlay?.frame = bounds
    }

    override func mouseDown(with event: NSEvent) {
        let rawPoint = convert(event.locationInWindow, from: nil)
        let layoutPoint = topBasedPoint(from: rawPoint)
        if headerView.frame.contains(layoutPoint) {
            let headerPoint = NSPoint(
                x: layoutPoint.x - headerView.frame.minX,
                y: layoutPoint.y - headerView.frame.minY
            )
            if searchField.frame.contains(headerPoint) {
                window?.makeFirstResponder(searchField)
            }
            return
        }

        if pager.frame.contains(layoutPoint) {
            let pagerPoint = NSPoint(
                x: layoutPoint.x - pager.frame.minX,
                y: layoutPoint.y - pager.frame.minY
            )

            if pager.hitTest(pagerPoint) == nil {
                onClose("pagerBlankClick")
            }

            return
        }

        if let folderOverlay, folderOverlay.frame.contains(layoutPoint) {
            return
        }

        onClose("outsideClick")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }

        let layoutPoint = topBasedPoint(from: point)

        if let folderOverlay {
            let overlayPoint = NSPoint(
                x: layoutPoint.x - folderOverlay.frame.minX,
                y: layoutPoint.y - folderOverlay.frame.minY
            )
            if folderOverlay.bounds.contains(overlayPoint) {
                logRootHitTest(rawPoint: point, layoutPoint: layoutPoint, result: "folderOverlay")
                return folderOverlay.hitTest(overlayPoint)
            }
        }

        if headerView.frame.contains(layoutPoint) {
            let headerPoint = NSPoint(
                x: layoutPoint.x - headerView.frame.minX,
                y: layoutPoint.y - headerView.frame.minY
            )
            let controls: [HeaderButton] = [
                closeButton,
                rescanButton,
                folderButton,
                editButton,
                filterButton,
                layoutButton,
                sortButton
            ]

            for control in controls {
                let controlPoint = NSPoint(
                    x: headerPoint.x - control.frame.minX,
                    y: headerPoint.y - control.frame.minY
                )
                if control.bounds.contains(controlPoint) {
                    logRootHitTest(
                        rawPoint: point,
                        layoutPoint: layoutPoint,
                        result: "header.control",
                        detail: control.debugName
                    )
                    return control.hitTest(controlPoint) ?? control
                }
            }

            if searchField.frame.contains(headerPoint) {
                let fieldPoint = NSPoint(
                    x: headerPoint.x - searchField.frame.minX,
                    y: headerPoint.y - searchField.frame.minY
                )
                logRootHitTest(
                    rawPoint: point,
                    layoutPoint: layoutPoint,
                    result: "header.search",
                    detail: "searchField"
                )
                return searchField.hitTest(fieldPoint) ?? searchField
            }

            logRootHitTest(rawPoint: point, layoutPoint: layoutPoint, result: "header.background")
            return headerView
        }

        if pager.frame.contains(layoutPoint) {
            let pagerPoint = NSPoint(
                x: layoutPoint.x - pager.frame.minX,
                y: layoutPoint.y - pager.frame.minY
            )
            if let result = pager.hitTest(pagerPoint) {
                logRootHitTest(
                    rawPoint: point,
                    layoutPoint: layoutPoint,
                    result: "pager",
                    detail: String(reflecting: type(of: result))
                )
                return result
            }

            logRootHitTest(
                rawPoint: point,
                layoutPoint: layoutPoint,
                result: "pager.blank",
                detail: "closeTarget"
            )
            return self
        }

        logRootHitTest(rawPoint: point, layoutPoint: layoutPoint, result: "outside.closeTarget")
        return self
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape()
        } else {
            super.keyDown(with: event)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        store.setSearchText(searchField.stringValue)
    }

    func focusSearch() {
        window?.makeFirstResponder(searchField)
    }

    private func configureBackground() {
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        addSubview(effectView)

        tintView.colors = [
            NSColor.black.withAlphaComponent(0.10),
            NSColor.black.withAlphaComponent(0.045),
            NSColor.white.withAlphaComponent(0.018),
            NSColor.black.withAlphaComponent(0.055)
        ]
        addSubview(tintView)
    }

    private func configureHeader() {
        headerView.material = .popover
        headerView.blendingMode = .withinWindow
        headerView.state = .active
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.035).cgColor
        headerView.layer?.cornerRadius = 33
        headerView.layer?.cornerCurve = .continuous
        headerView.layer?.borderWidth = 1
        headerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.13).cgColor
        headerView.layer?.shadowColor = NSColor.black.cgColor
        headerView.layer?.shadowOpacity = 0.10
        headerView.layer?.shadowRadius = 24
        headerView.layer?.shadowOffset = CGSize(width: 0, height: -10)
        addSubview(headerView)

        searchIconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        searchIconView.imageScaling = .scaleProportionallyDown
        searchIconView.contentTintColor = .white.withAlphaComponent(0.72)
        searchIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        searchField.cell = VerticallyCenteredTextFieldCell()
        searchField.delegate = self
        searchField.placeholderString = L10n.text(.searchPlaceholder)
        searchField.font = .systemFont(ofSize: 18, weight: .semibold)
        searchField.textColor = .white
        searchField.focusRingType = .none
        searchField.backgroundColor = .clear
        searchField.drawsBackground = false
        searchField.isBezeled = false
        searchField.isBordered = false
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.isEnabled = true
        searchField.usesSingleLineMode = true
        searchField.lineBreakMode = .byTruncatingTail
        searchField.setAccessibilityLabel(L10n.text(.searchAccessibilityLabel))
        searchField.setAccessibilityHelp(L10n.text(.searchAccessibilityHelp))
        headerView.addSubview(searchField)
        headerView.addSubview(searchIconView, positioned: .above, relativeTo: searchField)

        configureButton(
            sortButton,
            symbol: "arrow.up.arrow.down",
            title: store.sortMode.title,
            toolTip: L10n.text(.sortTooltip),
            debugName: "sort",
            action: #selector(showSortMenu)
        )
        configureButton(
            layoutButton,
            symbol: "rectangle.grid.3x2",
            title: store.gridLayout.title,
            toolTip: L10n.text(.layoutTooltip),
            debugName: "layout",
            action: #selector(showLayoutMenu)
        )
        configureButton(
            editButton,
            symbol: "slider.horizontal.3",
            title: nil,
            toolTip: L10n.text(.editTooltip),
            debugName: "edit",
            action: #selector(toggleEditing)
        )
        configureButton(
            filterButton,
            symbol: "line.3.horizontal.decrease.circle",
            title: nil,
            toolTip: L10n.text(.filterTooltip),
            debugName: "filter",
            action: #selector(showFilterMenu)
        )
        configureButton(
            folderButton,
            symbol: "folder.badge.plus",
            title: nil,
            toolTip: L10n.text(.newFolder),
            debugName: "folder",
            action: #selector(createFolder)
        )
        configureButton(
            rescanButton,
            symbol: "arrow.clockwise",
            title: nil,
            toolTip: L10n.text(.rescan),
            debugName: "rescan",
            action: #selector(rescanApplications)
        )
        configureButton(
            closeButton,
            symbol: "xmark",
            title: nil,
            toolTip: L10n.text(.close),
            debugName: "close",
            action: #selector(closeLauncher)
        )
    }

    /// 配置顶部栏按钮的图标、标题、提示和动作。
    ///
    /// - Parameters:
    ///   - button: 需要配置的自定义顶部控件。
    ///   - symbol: SF Symbol 名称。
    ///   - title: 可选按钮文字；为 `nil` 时只显示图标。
    ///   - toolTip: 鼠标提示和辅助功能标签。
    ///   - action: 用户点击后发送给根视图的 Selector。
    private func configureButton(
        _ button: HeaderButton,
        symbol: String,
        title: String?,
        toolTip: String,
        debugName: String,
        action: Selector
    ) {
        button.target = self
        button.action = action
        button.debugName = debugName
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        button.title = title ?? ""
        button.textFont = .systemFont(ofSize: 13.5, weight: .semibold)
        button.contentTintColor = .white.withAlphaComponent(0.84)
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip)
        headerView.addSubview(button)
    }

    private func configurePager() {
        addSubview(pager)
        addSubview(pageDots)
        pageDots.onSelect = { [weak self] index in
            guard let self else { return }
            self.store.changePage(by: index - self.store.pageIndex)
        }
    }

    private func configureStatusLabel() {
        statusLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail
        addSubview(statusLabel)
    }

    /// 将 Store 粗粒度通知路由到最小范围的 UI 更新。
    ///
    /// - Parameter change: Store 发出的界面变更类型。
    private func handleStoreChange(_ change: LauncherStoreChange) {
        switch change {
        case let .content(animated):
            reload(animated: animated)
            refreshFolderOverlay()
        case .state:
            updateHeader()
            updateStatus()
        case .search:
            pager.reloadSearchResults()
            updatePageDots()
        case .layoutChanged:
            pager.reloadForLayoutChange()
            updatePageDots()
            updateHeader()
            updateStatus()
        case let .filterModeChanged(previousPageIndex):
            pager.reloadForFilterModeChange(from: previousPageIndex, to: 0)
            updatePageDots()
            updateHeader()
            updateStatus()
        case let .folderCreated(_, previousPageIndex, targetPageIndex):
            pager.reloadForFolderCreation(from: previousPageIndex, to: targetPageIndex)
            updatePageDots()
            updateHeader()
            updateStatus()
            refreshFolderOverlay()
        case .dragPreview:
            pager.scheduleDragPreviewAnimation()
            updatePageDots()
        case .pageDrag:
            pager.setPage(index: store.pageIndex, dragOffset: store.pageDragOffset, animated: false)
        case let .pageSettled(previousIndex, previousOffset):
            pager.setPage(
                index: store.pageIndex,
                dragOffset: 0,
                animated: true,
                previousIndex: previousIndex,
                previousOffset: previousOffset
            )
            updatePageDots()
        case .editing:
            pager.updateEditingState()
            updateHeader()
        case .presentation:
            searchField.stringValue = ""
            reload(animated: false)
            preparePresentationAnimation()
        }
    }

    /// 重载 Tile 内容，并同步顶部栏、状态区和分页指示器。
    ///
    /// - Parameter animated: 是否使用现有内容重排动画。
    private func reload(animated: Bool) {
        pager.reload(animated: animated)
        updatePageDots()
        updateHeader()
        updateStatus()
    }

    private func updatePageDots() {
        pageDots.pageCount = store.pageCount
        pageDots.currentPage = min(store.pageIndex, max(0, store.pageCount - 1))
    }

    private func updateHeader() {
        sortButton.title = store.sortMode.title
        layoutButton.title = store.gridLayout.title
        filterButton.image = NSImage(
            systemSymbolName: store.appFilterMode == .visibleOnly
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        filterButton.toolTip = store.appFilterMode.title
        editButton.image = NSImage(
            systemSymbolName: store.isInManualEditMode ? "checkmark" : "slider.horizontal.3",
            accessibilityDescription: nil
        )
        editButton.toolTip = store.isInManualEditMode ? L10n.text(.doneEditingTooltip) : L10n.text(.editTooltip)
        rescanButton.isEnabled = store.contentState != .refreshing
        rescanButton.toolTip = store.contentState == .refreshing
            ? L10n.text(.refreshingApplications)
            : L10n.text(.rescan)
        headerView.needsLayout = true
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func updateStatus() {
        if let message = store.statusMessage {
            statusLabel.stringValue = message
            statusLabel.isHidden = false
            return
        }

        switch store.contentState {
        case .empty:
            statusLabel.stringValue = L10n.text(.noApplicationsFound)
            statusLabel.isHidden = false
        case let .failed(error):
            statusLabel.stringValue = error.message
            statusLabel.isHidden = false
        case .ready, .refreshing:
            statusLabel.stringValue = ""
            statusLabel.isHidden = true
        }
    }

    /// 在 Panel 可见前设置初始透明度和变换。
    ///
    /// 动画参数用于保持当前展示体验，不应随普通业务修改调整。
    func preparePresentationAnimation() {
        layoutSubtreeIfNeeded()
        pager.suspendInteraction(for: 0.44)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        for view in [headerView, pager, pageDots] {
            view.wantsLayer = true
            view.layer?.removeAllAnimations()
        }

        headerView.alphaValue = 0
        pager.alphaValue = 0
        pageDots.alphaValue = 0

        if reduceMotion {
            headerView.layer?.transform = CATransform3DIdentity
            pager.layer?.transform = CATransform3DIdentity
            pageDots.layer?.transform = CATransform3DIdentity
        } else {
            headerView.layer?.transform = CATransform3DMakeTranslation(0, -12, 0)
            var pagerTransform = CATransform3DMakeTranslation(0, 18, 0)
            pagerTransform = CATransform3DScale(pagerTransform, 0.965, 0.965, 1)
            pager.layer?.transform = pagerTransform
            pageDots.layer?.transform = CATransform3DMakeTranslation(0, 10, 0)
        }
    }

    /// 在 `LauncherController.show` 后将预备状态动画恢复到正常状态。
    func playPresentationAnimation() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            headerView.layer?.transform = CATransform3DIdentity
            pager.layer?.transform = CATransform3DIdentity
            pageDots.layer?.transform = CATransform3DIdentity
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                headerView.animator().alphaValue = 1
                pager.animator().alphaValue = 1
                pageDots.animator().alphaValue = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self.searchField)
            }
            return
        }

        animatePresentationTransform(
            of: headerView,
            duration: 0.30,
            timing: CAMediaTimingFunction(controlPoints: 0.18, 0.78, 0.22, 1)
        )
        animatePresentationTransform(
            of: pager,
            duration: 0.38,
            timing: CAMediaTimingFunction(controlPoints: 0.16, 0.76, 0.20, 1)
        )
        animatePresentationTransform(
            of: pageDots,
            duration: 0.34,
            timing: CAMediaTimingFunction(controlPoints: 0.18, 0.78, 0.22, 1)
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.78, 0.22, 1)
            headerView.animator().alphaValue = 1
            pager.animator().alphaValue = 1
            pageDots.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self.searchField)
        }
    }

    func animatePresentationIn(completion: (@MainActor @Sendable () -> Void)? = nil) {
        wantsLayer = true
        layer?.removeAnimation(forKey: rootPresentationAnimationKey)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        alphaValue = 0
        layer?.transform = reduceMotion
            ? CATransform3DIdentity
            : CATransform3DMakeScale(0.985, 0.985, 1)

        let duration: TimeInterval = reduceMotion ? 0.08 : 0.18
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.78, 0.22, 1.0)
            animator().alphaValue = 1
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let self else {
                completion?()
                return
            }
            self.alphaValue = 1
            self.layer?.transform = CATransform3DIdentity
            completion?()
        }

        guard !reduceMotion, let layer else {
            return
        }

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: CATransform3DMakeScale(0.985, 0.985, 1))
        animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.78, 0.22, 1.0)
        layer.transform = CATransform3DIdentity
        layer.add(animation, forKey: rootPresentationAnimationKey)
    }

    func animatePresentationOut(completion: @escaping @MainActor @Sendable () -> Void) {
        wantsLayer = true
        layer?.removeAnimation(forKey: rootPresentationAnimationKey)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration: TimeInterval = reduceMotion ? 0.08 : 0.14

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.0, 0.67, 1.0)
            animator().alphaValue = 0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            completion()
        }

        guard !reduceMotion, let layer else {
            return
        }

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        animation.toValue = NSValue(caTransform3D: CATransform3DMakeScale(0.985, 0.985, 1))
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.0, 0.67, 1.0)
        layer.transform = CATransform3DMakeScale(0.985, 0.985, 1)
        layer.add(animation, forKey: rootPresentationAnimationKey)
    }

    /// 将指定视图从当前变换动画恢复到单位矩阵。
    ///
    /// - Parameters:
    ///   - view: 需要执行入场变换的视图。
    ///   - duration: 动画时长，单位为秒。
    ///   - timing: Core Animation 时间函数。
    private func animatePresentationTransform(
        of view: NSView,
        duration: CFTimeInterval,
        timing: CAMediaTimingFunction
    ) {
        guard let layer = view.layer else {
            return
        }

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: layer.transform)
        animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        animation.duration = duration
        animation.timingFunction = timing
        layer.transform = CATransform3DIdentity
        layer.add(animation, forKey: "presentationEntrance")
    }

    private func safeTopPadding() -> CGFloat {
        guard let screen = window?.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return 62
        }
        let reservedTop = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        return max(62, reservedTop + 18)
    }

    @objc private func showSortMenu() {
        LumaEventLog.shared.writeInteraction(.header, "header.action.showSortMenu")
        let menu = NSMenu()
        menu.addItem(menuItem(L10n.text(.sortCustom), action: #selector(setCustomSort), state: store.sortMode == .custom))
        menu.addItem(menuItem(L10n.text(.sortName), action: #selector(setNameSort), state: store.sortMode == .name))
        popUpHeaderMenu(menu, from: sortButton, minimumWidth: 180)
    }

    @objc private func showLayoutMenu() {
        LumaEventLog.shared.writeInteraction(.header, "header.action.showLayoutMenu")
        let menu = NSMenu()
        let countItem = NSMenuItem(title: L10n.text(.appsPerPage(store.gridLayout.itemsPerPage)), action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        menu.addItem(countItem)
        menu.addItem(.separator())

        let rowsItem = NSMenuItem(title: L10n.text(.layoutRows), action: nil, keyEquivalent: "")
        let rowsMenu = NSMenu()
        for rows in LauncherGridLayout.allowedRows {
            let item = NSMenuItem(title: L10n.text(.rowCount(rows)), action: #selector(setRows(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = rows
            item.state = rows == store.gridLayout.rows ? .on : .off
            rowsMenu.addItem(item)
        }
        rowsItem.submenu = rowsMenu
        menu.addItem(rowsItem)

        let columnsItem = NSMenuItem(title: L10n.text(.layoutColumns), action: nil, keyEquivalent: "")
        let columnsMenu = NSMenu()
        for columns in LauncherGridLayout.allowedColumns {
            let item = NSMenuItem(title: L10n.text(.columnCount(columns)), action: #selector(setColumns(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = columns
            item.state = columns == store.gridLayout.columns ? .on : .off
            columnsMenu.addItem(item)
        }
        columnsItem.submenu = columnsMenu
        menu.addItem(columnsItem)
        menu.addItem(.separator())
        let reset = NSMenuItem(title: L10n.text(.layoutDefault), action: #selector(resetLayout), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        popUpHeaderMenu(menu, from: layoutButton, minimumWidth: 240)
    }

    @objc private func showFilterMenu() {
        LumaEventLog.shared.writeInteraction(.header, "header.action.showFilterMenu")
        let menu = NSMenu()
        menu.addItem(menuItem(L10n.text(.filterVisible), action: #selector(showVisibleAppsOnly), state: store.appFilterMode == .visibleOnly))
        menu.addItem(menuItem(L10n.text(.filterAll), action: #selector(showAllApps), state: store.appFilterMode == .all))
        menu.addItem(menuItem(L10n.text(.filterHidden), action: #selector(showHiddenAppsOnly), state: store.appFilterMode == .hiddenOnly))
        popUpHeaderMenu(menu, from: filterButton, minimumWidth: 220)
    }

    private func popUpHeaderMenu(
        _ menu: NSMenu,
        from button: HeaderButton,
        minimumWidth: CGFloat = 220
    ) {
        menu.minimumWidth = minimumWidth
        let anchor = NSPoint(x: 0, y: -6)
        LumaEventLog.shared.writeInteraction(
            .header,
            "header.menu.popup",
            fields: [
                "button": button.debugName,
                "buttonFrame": lumaLogRect(button.frame),
                "buttonBounds": lumaLogRect(button.bounds),
                "anchor": lumaLogPoint(anchor),
                "minimumWidth": minimumWidth
            ]
        )
        menu.popUp(positioning: nil, at: anchor, in: button)
    }

    /// 创建带选中状态的菜单项。
    ///
    /// - Parameters:
    ///   - title: 菜单项显示文本。
    ///   - action: 选择菜单项时执行的 Selector。
    ///   - state: 是否显示勾选状态。
    /// - Returns: 已绑定根视图 target 的菜单项。
    private func menuItem(_ title: String, action: Selector, state: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = state ? .on : .off
        return item
    }

    @objc private func setCustomSort() {
        store.setSortMode(.custom)
    }

    @objc private func setNameSort() {
        store.setSortMode(.name)
    }

    @objc private func showVisibleAppsOnly() {
        store.setAppFilterMode(.visibleOnly)
    }

    @objc private func showAllApps() {
        store.setAppFilterMode(.all)
    }

    @objc private func showHiddenAppsOnly() {
        store.setAppFilterMode(.hiddenOnly)
    }

    @objc private func setRows(_ sender: NSMenuItem) {
        guard let rows = sender.representedObject as? Int else { return }
        store.setGridRows(rows)
    }

    @objc private func setColumns(_ sender: NSMenuItem) {
        guard let columns = sender.representedObject as? Int else { return }
        store.setGridColumns(columns)
    }

    @objc private func resetLayout() {
        store.resetGridLayout()
    }

    @objc private func toggleEditing() {
        LumaEventLog.shared.writeInteraction(.header, "header.action.toggleEditing")
        store.toggleEditing()
    }

    @objc private func createFolder() {
        LumaEventLog.shared.writeInteraction(.header, "header.action.createFolder")
        showNamePrompt(title: L10n.text(.newFolder), initialValue: "") { [weak self] name in
            self?.store.createFolder(named: name)
        }
    }

    @objc private func rescanApplications() {
        LumaEventLog.shared.writeInteraction(.header, "header.action.rescan")
        store.requestRefresh()
    }

    @objc private func closeLauncher() {
        LumaEventLog.shared.writeInteraction(.header, "header.action.close")
        onClose("closeButton")
    }

    /// 显示新建或重命名文件夹的文本输入弹窗。
    ///
    /// - Parameters:
    ///   - title: 弹窗标题，同时决定确认按钮使用“Create”还是“Rename”。
    ///   - initialValue: 输入框初始内容。
    ///   - completion: 用户确认后接收输入文本的回调。
    private func showNamePrompt(title: String, initialValue: String, completion: @escaping (String) -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: title == L10n.text(.newFolder) ? L10n.text(.create) : L10n.text(.rename))
        alert.addButton(withTitle: L10n.text(.cancel))

        let input = NSTextField(string: initialValue)
        input.frame = NSRect(x: 0, y: 0, width: 280, height: 28)
        alert.accessoryView = input
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            completion(input.stringValue)
        }
    }

    /// 创建文件夹浮层，并将其中操作意图连接回 Store。
    ///
    /// - Parameter folder: 需要展示的文件夹模型。
    private func showFolder(_ folder: LauncherFolder) {
        folderOverlay?.removeFromSuperview()
        let overlay = FolderOverlayView(frame: bounds, folder: folder, store: store)
        overlay.onClose = { [weak self] in
            self?.folderOverlay?.removeFromSuperview()
            self?.folderOverlay = nil
        }
        overlay.onLaunch = { [weak self] app in
            self?.store.launchApp(app)
            self?.onClose("appLaunch")
        }
        overlay.onRename = { [weak self] folder in
            self?.showNamePrompt(title: L10n.text(.renameFolder), initialValue: folder.name) { name in
                self?.store.renameFolder(id: folder.id, to: name)
            }
        }
        folderOverlay = overlay
        addSubview(overlay)
        overlay.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            overlay.animator().alphaValue = 1
        }
    }

    private func refreshFolderOverlay() {
        guard let overlay = folderOverlay else { return }
        guard let folder = store.folder(withID: overlay.folderID) else {
            overlay.removeFromSuperview()
            folderOverlay = nil
            return
        }
        overlay.update(folder: folder)
    }

    private func topBasedPoint(from point: NSPoint) -> NSPoint {
        NSPoint(x: point.x, y: bounds.height - point.y)
    }

    private func logRootHitTest(
        rawPoint: NSPoint,
        layoutPoint: NSPoint,
        result: String,
        detail: String? = nil
    ) {
        guard interactionLogThrottle.shouldLog("root.hitTest.\(result).\(detail ?? "none")", interval: 0.15) else {
            return
        }
        LumaEventLog.shared.writeInteraction(
            .hitTest,
            "root.hitTest",
            fields: [
                "rawPoint": lumaLogPoint(rawPoint),
                "layoutPoint": lumaLogPoint(layoutPoint),
                "result": result,
                "detail": detail ?? "nil",
                "headerFrame": lumaLogRect(headerView.frame),
                "pagerFrame": lumaLogRect(pager.frame),
                "folderOverlayVisible": folderOverlay != nil
            ]
        )
    }
}

extension LauncherRootView: LauncherPagerDelegate {
    func pager(_ pager: LauncherPagerView, open tile: LauncherTile) {
        switch tile.kind {
        case let .app(app):
            store.launchApp(app)
            onClose("appLaunch")
        case let .folder(folder, _):
            showFolder(folder)
        }
    }

    func pagerDidRequestEditing(_ pager: LauncherPagerView) {
        store.beginManualEditing()
    }

    func pager(_ pager: LauncherPagerView, contextMenuFor tile: LauncherTile) -> NSMenu {
        let menu = NSMenu()
        switch tile.kind {
        case let .app(app):
            let open = ClosureMenuItem(title: L10n.text(.open)) { [weak self] in
                self?.store.launchApp(app)
                self?.onClose("appLaunch")
            }
            menu.addItem(open)
            menu.addItem(ClosureMenuItem(title: L10n.text(.showInFinder)) { [weak self] in
                self?.store.revealInFinder(app)
            })
            menu.addItem(ClosureMenuItem(title: store.isAppHidden(app.id) ? L10n.text(.unhideApp) : L10n.text(.hideApp)) { [weak self] in
                guard let self else { return }
                self.store.setHidden(!self.store.isAppHidden(app.id), for: app.id)
            })

            let foldersItem = NSMenuItem(title: L10n.text(.moveToFolder), action: nil, keyEquivalent: "")
            let foldersMenu = NSMenu()
            for folder in store.folders {
                foldersMenu.addItem(ClosureMenuItem(title: folder.name) { [weak self] in
                    self?.store.addApp(app.id, to: folder.id)
                })
            }
            if !store.folders.isEmpty {
                foldersMenu.addItem(.separator())
            }
            foldersMenu.addItem(ClosureMenuItem(title: L10n.text(.newFolder)) { [weak self] in
                self?.store.createFolder(containing: [app.id])
            })
            foldersItem.submenu = foldersMenu
            menu.addItem(foldersItem)
        case let .folder(folder, _):
            menu.addItem(ClosureMenuItem(title: L10n.text(.open)) { [weak self] in
                self?.showFolder(folder)
            })
            menu.addItem(ClosureMenuItem(title: L10n.text(.rename)) { [weak self] in
                self?.showNamePrompt(title: L10n.text(.renameFolder), initialValue: folder.name) { name in
                    self?.store.renameFolder(id: folder.id, to: name)
                }
            })
            menu.addItem(ClosureMenuItem(title: L10n.text(.deleteFolder)) { [weak self] in
                self?.store.deleteFolder(id: folder.id)
            })
        }
        return menu
    }
}
