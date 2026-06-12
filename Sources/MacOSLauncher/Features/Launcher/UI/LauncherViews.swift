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
        let headerWidth = min(max(960, bounds.width - 260), 1450)
        headerView.frame = NSRect(
            x: floor((bounds.width - headerWidth) / 2),
            y: top,
            width: headerWidth,
            height: 66
        )

        let buttonHeight: CGFloat = 50
        let controlWidths: [CGFloat] = [
            L10n.isChinese ? 116 : 132,
            104,
            58, 58, 58, 58, 58
        ]
        let controlSpacing: CGFloat = 7
        let controlsWidth = controlWidths.reduce(0, +)
            + CGFloat(controlWidths.count - 1) * controlSpacing
        let searchAreaWidth = max(320, headerWidth - controlsWidth - 54)
        let searchCenterY = headerView.bounds.midY
        searchField.frame = NSRect(
            x: 18,
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

        var x = 18 + searchAreaWidth + 10
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
            let result = pager.hitTest(pagerPoint)
            logRootHitTest(
                rawPoint: point,
                layoutPoint: layoutPoint,
                result: result == nil ? "pager.nil" : "pager",
                detail: result.map { String(reflecting: type(of: $0)) }
            )
            return result
        }

        logRootHitTest(rawPoint: point, layoutPoint: layoutPoint, result: "outside")
        return nil
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
            NSColor.black.withAlphaComponent(0.08),
            NSColor.black.withAlphaComponent(0.015),
            NSColor.black.withAlphaComponent(0.06)
        ]
        addSubview(tintView)
    }

    private func configureHeader() {
        headerView.material = .hudWindow
        headerView.blendingMode = .withinWindow
        headerView.state = .active
        headerView.wantsLayer = true
        headerView.layer?.cornerRadius = 33
        headerView.layer?.cornerCurve = .continuous
        headerView.layer?.borderWidth = 1
        headerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        headerView.layer?.shadowColor = NSColor.black.cgColor
        headerView.layer?.shadowOpacity = 0.14
        headerView.layer?.shadowRadius = 18
        headerView.layer?.shadowOffset = CGSize(width: 0, height: -8)
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
        searchField.setAccessibilityLabel("Search applications")
        searchField.setAccessibilityHelp("Type an application or folder name.")
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
            systemSymbolName: store.isEditing ? "checkmark" : "slider.horizontal.3",
            accessibilityDescription: nil
        )
        editButton.toolTip = store.isEditing ? L10n.text(.doneEditingTooltip) : L10n.text(.editTooltip)
        rescanButton.isEnabled = store.contentState != .refreshing
        rescanButton.toolTip = store.contentState == .refreshing
            ? L10n.text(.refreshingApplications)
            : L10n.text(.rescan)
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

        for view in [headerView, pager, pageDots] {
            view.wantsLayer = true
            view.layer?.removeAllAnimations()
        }

        headerView.alphaValue = 0
        pager.alphaValue = 0
        pageDots.alphaValue = 0

        headerView.layer?.transform = CATransform3DMakeTranslation(0, -12, 0)
        var pagerTransform = CATransform3DMakeTranslation(0, 18, 0)
        pagerTransform = CATransform3DScale(pagerTransform, 0.965, 0.965, 1)
        pager.layer?.transform = pagerTransform
        pageDots.layer?.transform = CATransform3DMakeTranslation(0, 10, 0)
    }

    /// 在 `LauncherController.show` 后将预备状态动画恢复到正常状态。
    func playPresentationAnimation() {
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
        popUpHeaderMenu(menu, from: sortButton)
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
        popUpHeaderMenu(menu, from: layoutButton)
    }

    @objc private func showFilterMenu() {
        LumaEventLog.shared.writeInteraction(.header, "header.action.showFilterMenu")
        let menu = NSMenu()
        menu.addItem(menuItem(L10n.text(.filterVisible), action: #selector(showVisibleAppsOnly), state: store.appFilterMode == .visibleOnly))
        menu.addItem(menuItem(L10n.text(.filterAll), action: #selector(showAllApps), state: store.appFilterMode == .all))
        menu.addItem(menuItem(L10n.text(.filterHidden), action: #selector(showHiddenAppsOnly), state: store.appFilterMode == .hiddenOnly))
        popUpHeaderMenu(menu, from: filterButton)
    }

    private func popUpHeaderMenu(_ menu: NSMenu, from button: NSView) {
        let anchor = NSPoint(
            x: floor(button.bounds.midX),
            y: button.bounds.maxY + 6
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
            context.duration = 0.16
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
        store.beginEditing()
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
    private let leadingReplica = NSImageView()
    private let trailingReplica = NSImageView()
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
            replica.imageScaling = .scaleAxesIndependently
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
            LumaEventLog.shared.writeInteraction(
                .hitTest,
                "pager.hitTest.result",
                fields: [
                    "result": "tile",
                    "tileID": tileView.tileID
                ]
            )
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
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
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
                view.update(tile: tile, metrics: metrics, isEditing: store.isEditing)
                if isNew {
                    view.alphaValue = animated ? 0 : 1
                }
            } else {
                view = LauncherTileView(
                    tile: tile,
                    store: store,
                    metrics: metrics,
                    isEditing: store.isEditing
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
            view.setEditing(store.isEditing, dragged: store.draggedTileID == view.tileID)
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
            suspendInteraction(for: 0.40)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.38
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.20,
                    0.72,
                    0.24,
                    1.0
                )
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

    /// 截取首尾页面快照，用于渲染连续循环翻页。
    private func refreshEdgeReplicas() {
        let start = CACurrentMediaTime()
        guard renderedPageCount > 1,
              let firstPage = pageViews[0],
              let lastPage = pageViews[renderedPageCount - 1] else {
            leadingReplica.image = nil
            trailingReplica.image = nil
            return
        }

        leadingReplica.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        trailingReplica.frame = NSRect(
            x: CGFloat(renderedPageCount + 1) * bounds.width,
            y: 0,
            width: bounds.width,
            height: bounds.height
        )
        leadingReplica.image = snapshot(of: lastPage)
        trailingReplica.image = snapshot(of: firstPage)
        LumaEventLog.shared.writeInteraction(
            .performance,
            "pager.refreshEdgeReplicas",
            fields: [
                "pages": renderedPageCount,
                "durationMS": Int((CACurrentMediaTime() - start) * 1_000)
            ]
        )
    }

    private func snapshot(of view: NSView) -> NSImage? {
        let start = CACurrentMediaTime()
        guard view.bounds.width > 0,
              view.bounds.height > 0,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }

        view.cacheDisplay(in: view.bounds, to: representation)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(representation)
        if interactionLogThrottle.shouldLog("pager.snapshot", interval: 0.20) {
            LumaEventLog.shared.writeInteraction(
                .performance,
                "pager.snapshot",
                fields: [
                    "size": lumaLogSize(view.bounds.size),
                    "durationMS": Int((CACurrentMediaTime() - start) * 1_000)
                ]
            )
        }
        return image
    }

    private func tile(atDraggingLocation location: NSPoint) -> LauncherTileView? {
        let rawLocalPoint = convert(location, from: nil)
        let flippedLocalPoint = NSPoint(
            x: rawLocalPoint.x,
            y: bounds.height - rawLocalPoint.y
        )
        let rawHit = hitTestTile(at: rawLocalPoint, from: self)
        let flippedHit = hitTestTile(at: flippedLocalPoint, from: self)

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

    private func hitTestTile(at point: NSPoint, from sourceView: NSView) -> LauncherTileView? {
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
            .first { $0.frame.contains(pagerPoint) }
        if let tileView {
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
            return
        }

        if dropTargetID != target.tileID {
            dropTargetID = target.tileID
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

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let draggedID = sender.draggingPasteboard.string(forType: .string),
              let target = tile(atDraggingLocation: sender.draggingLocation),
              target.tileID != draggedID else {
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
        updateDropTarget(draggedID: draggedID, target: target)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropTargetID = nil
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        var didCommitDrop = false
        defer {
            currentDragCommitted = didCommitDrop
            dropTargetID = nil
            setPageRasterizationEnabled(true)
            refreshEdgeReplicas()
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
        let dragID = store.currentDragID
        let shouldCommit =
            currentDragCommitted
            || (operation.contains(.move) && store.hasPendingDragPreview)
        store.endDraggingTile(commit: shouldCommit)
        LumaEventLog.shared.writeInteraction(
            .drag,
            "tile.drag.end",
            fields: [
                "tileID": view.tileID,
                "dragID": dragID ?? "nil",
                "committed": shouldCommit,
                "operation": operation.rawValue
            ]
        )
        currentDragCommitted = false
        setPageRasterizationEnabled(true)
        refreshEdgeReplicas()
    }

    func tileView(_ view: LauncherTileView, draggingUpdatedWith draggedID: String) -> NSDragOperation {
        guard store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        updateDropTarget(draggedID: draggedID, target: view)
        return .move
    }

    func tileView(_ view: LauncherTileView, performDropWith draggedID: String, at windowLocation: NSPoint) -> Bool {
        var didCommitDrop = false
        defer {
            currentDragCommitted = didCommitDrop
            dropTargetID = nil
            setPageRasterizationEnabled(true)
            refreshEdgeReplicas()
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
              target.tile.app != nil else {
            return false
        }
        return target.wantsCreateFolderDrop(atWindowLocation: windowLocation)
    }

    func tileView(_ view: LauncherTileView, contextMenuFor tile: LauncherTile) -> NSMenu {
        delegate?.pager(self, contextMenuFor: tile) ?? NSMenu()
    }
}

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
    private let editBadge = NSImageView()
    private var metrics: LauncherGridMetrics
    private var isEditing = false
    private var isDraggingTile = false
    private var isHovering = false
    private var trackingAreaToken: NSTrackingArea?
    private var mouseDownEvent: NSEvent?
    private var longPressWorkItem: DispatchWorkItem?
    private var longPressTriggered = false
    private var pressedTile: LauncherTile?
    private var renderedTile: LauncherTile?
    private var renderedIconSize: CGFloat = 0
    private var isHiddenApp = false
    private let interactionLogThrottle = InteractionLogThrottle()
    private let wiggleAnimationKey = "luma.tile.wiggle"

    override var isFlipped: Bool { true }

    /// 创建 Tile 视图。
    ///
    /// - Parameters:
    ///   - tile: 当前展示的应用或文件夹模型。
    ///   - store: 提供图标和隐藏状态的业务 Store。
    ///   - metrics: 当前网格布局计算结果。
    ///   - isEditing: 创建时是否处于编辑模式。
    init(
        tile: LauncherTile,
        store: LauncherStore,
        metrics: LauncherGridMetrics,
        isEditing: Bool
    ) {
        self.tile = tile
        self.store = store
        self.metrics = metrics
        self.isEditing = isEditing
        super.init(frame: .zero)

        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tile.title)
        layer?.drawsAsynchronously = true
        layer?.shouldRasterize = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.shadowColor = NSColor.black.cgColor
        iconView.layer?.shadowOpacity = 0.28
        iconView.layer?.shadowRadius = 12
        iconView.layer?.shadowOffset = CGSize(width: 0, height: -6)
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.wraps = true
        titleLabel.cell?.usesSingleLineMode = false
        titleLabel.wantsLayer = true
        titleLabel.layer?.shadowColor = NSColor.black.cgColor
        titleLabel.layer?.shadowOpacity = 0.45
        titleLabel.layer?.shadowRadius = 2
        titleLabel.layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(titleLabel)

        editBadge.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Drag")
        editBadge.contentTintColor = .white.withAlphaComponent(0.82)
        editBadge.wantsLayer = true
        editBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.30).cgColor
        editBadge.layer?.cornerRadius = 13
        editBadge.isHidden = true
        addSubview(editBadge)

        registerForDraggedTypes([.string])
        update(tile: tile, metrics: metrics, isEditing: isEditing)
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
        editBadge.frame = NSRect(
            x: iconView.frame.maxX - 20,
            y: max(0, iconView.frame.minY - 5),
            width: 26,
            height: 26
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
        bounds.contains(point) ? self : nil
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
                "isEditing": isEditing,
                "point": lumaLogPoint(convert(event.locationInWindow, from: nil))
            ]
        )
        if isEditing {
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.longPressTriggered = true
            LumaEventLog.shared.writeInteraction(.tile, "tile.longPress", fields: ["tileID": self.tile.id])
            self.delegate?.tileViewDidRequestEditing(self)
        }
        longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: workItem)
    }

    /// 达到移动距离和长按阈值后启动原生拖拽。
    ///
    /// - Parameter event: 当前鼠标拖动事件。
    override func mouseDragged(with event: NSEvent) {
        guard !isDraggingTile, let initialEvent = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - initialEvent.locationInWindow.x
        let dy = event.locationInWindow.y - initialEvent.locationInWindow.y
        guard hypot(dx, dy) > 4 else { return }

        if !isEditing, !longPressTriggered {
            guard event.timestamp - initialEvent.timestamp >= 0.32 else {
                return
            }
            longPressTriggered = true
            delegate?.tileViewDidRequestEditing(self)
        }

        longPressWorkItem?.cancel()
        longPressWorkItem = nil
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
        draggingItem.setDraggingFrame(iconView.frame, contents: iconView.image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
        updateAppearance(animated: true)
    }

    override func mouseUp(with event: NSEvent) {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        defer {
            mouseDownEvent = nil
            pressedTile = nil
        }

        guard !isDraggingTile, !longPressTriggered, !isEditing else { return }
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
        updateAppearance(animated: true)
    }

    /// 复用视图，只更新发生变化的模型、图标、布局和编辑状态。
    ///
    /// - Parameters:
    ///   - tile: 最新 Tile 模型。
    ///   - metrics: 最新网格布局计算结果。
    ///   - isEditing: 当前是否处于编辑模式。
    func update(tile: LauncherTile, metrics: LauncherGridMetrics, isEditing: Bool) {
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
        let editingChanged = self.isEditing != isEditing
        let hiddenState = tile.app.map { store.isAppHidden($0.id) } ?? false

        self.tile = tile
        setAccessibilityLabel(tile.title)
        if tile.folder != nil {
            setAccessibilityHelp("Folder. Press to open.")
        } else {
            setAccessibilityHelp("Application. Press to launch.")
        }
        self.metrics = metrics
        self.isEditing = isEditing
        isHiddenApp = hiddenState
        if titleLabel.stringValue != tile.title {
            titleLabel.stringValue = tile.title
        }
        if needsNewIcon {
            iconView.image = image(for: tile)
        }
        renderedTile = tile
        renderedIconSize = metrics.iconSize

        if editingChanged || editBadge.isHidden == isEditing {
            editBadge.isHidden = true
            updateJiggleAnimation()
        }
        if metricsChanged {
            needsLayout = true
        }
        if wasUnrendered {
            updateAppearance(animated: false)
        }
    }

    func setEditing(_ editing: Bool, dragged: Bool) {
        isEditing = editing
        isDraggingTile = dragged
        editBadge.isHidden = true
        updateJiggleAnimation()
        updateAppearance(animated: true)
    }

    func wantsCreateFolderDrop(atWindowLocation location: NSPoint) -> Bool {
        let localPoint = convert(location, from: nil)
        guard iconView.frame.contains(localPoint) else {
            return false
        }

        let inset = max(12, min(iconView.frame.width, iconView.frame.height) * 0.24)
        return iconView.frame.insetBy(dx: inset, dy: inset).contains(localPoint)
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

    /// 应用 Hover、隐藏和拖拽视觉状态，不修改 Tile 业务数据。
    ///
    /// - Parameter animated: 是否执行现有外观过渡动画。
    private func updateAppearance(animated: Bool) {
        let visibilityAlpha: CGFloat = isHiddenApp ? 0.62 : 1
        let targetAlpha: CGFloat = (isDraggingTile ? 0.42 : 1) * visibilityAlpha
        let targetScale: CGFloat = isHovering ? 1.014 : 1
        let targetTransform = CATransform3DMakeScale(targetScale, targetScale, 1)
        titleLabel.textColor = NSColor.white.withAlphaComponent(isHiddenApp ? 0.76 : 1)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                iconView.animator().alphaValue = targetAlpha
                titleLabel.animator().alphaValue = visibilityAlpha
            }

            if let layer = iconView.layer {
                let animation = CABasicAnimation(keyPath: "transform")
                animation.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
                animation.toValue = NSValue(caTransform3D: targetTransform)
                animation.duration = 0.28
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.transform = targetTransform
                layer.add(animation, forKey: "hoverScale")
            }
        } else {
            iconView.alphaValue = targetAlpha
            titleLabel.alphaValue = visibilityAlpha
            iconView.layer?.transform = targetTransform
        }
    }

    private func updateJiggleAnimation() {
        if isEditing, !isDraggingTile {
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
