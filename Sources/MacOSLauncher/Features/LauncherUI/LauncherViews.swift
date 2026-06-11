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
    private let onClose: () -> Void
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

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// 创建启动器根视图。
    ///
    /// - Parameters:
    ///   - frame: 根视图初始尺寸。
    ///   - store: 启动器业务状态。
    ///   - onClose: 用户请求关闭启动器时执行的闭包。
    ///   - onEscape: 用户按 Escape 时执行的闭包。
    init(frame: NSRect, store: LauncherStore, onClose: @escaping () -> Void, onEscape: @escaping () -> Void) {
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
        let headerWidth = min(max(900, bounds.width - 260), 1450)
        headerView.frame = NSRect(
            x: floor((bounds.width - headerWidth) / 2),
            y: top,
            width: headerWidth,
            height: 66
        )

        let buttonHeight: CGFloat = 50
        let controlWidths: [CGFloat] = [138, 112, 58, 58, 58, 58, 58]
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
        let point = convert(event.locationInWindow, from: nil)
        if headerView.frame.contains(point) {
            let headerPoint = convert(point, to: headerView)
            if searchField.frame.contains(headerPoint) {
                window?.makeFirstResponder(searchField)
            }
            return
        }
        onClose()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }

        if let folderOverlay {
            let overlayPoint = convert(point, to: folderOverlay)
            if folderOverlay.bounds.contains(overlayPoint) {
                return folderOverlay.hitTest(overlayPoint)
            }
        }

        let headerPoint = convert(point, to: headerView)
        if headerView.bounds.contains(headerPoint) {
            if searchField.frame.contains(headerPoint) {
                let fieldPoint = headerView.convert(headerPoint, to: searchField)
                return searchField.hitTest(fieldPoint) ?? searchField
            }

            let controls: [NSView] = [
                closeButton,
                rescanButton,
                folderButton,
                editButton,
                filterButton,
                layoutButton,
                sortButton
            ]

            for control in controls {
                let controlPoint = headerView.convert(headerPoint, to: control)
                if control.bounds.contains(controlPoint) {
                    return control.hitTest(controlPoint) ?? control
                }
            }

            return headerView
        }

        return super.hitTest(point)
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
        searchField.placeholderString = "Search apps"
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
            toolTip: "Sort",
            action: #selector(showSortMenu)
        )
        configureButton(
            layoutButton,
            symbol: "rectangle.grid.3x2",
            title: store.gridLayout.title,
            toolTip: "Layout",
            action: #selector(showLayoutMenu)
        )
        configureButton(
            editButton,
            symbol: "slider.horizontal.3",
            title: nil,
            toolTip: "Edit",
            action: #selector(toggleEditing)
        )
        configureButton(
            filterButton,
            symbol: "line.3.horizontal.decrease.circle",
            title: nil,
            toolTip: "Filter Apps",
            action: #selector(showFilterMenu)
        )
        configureButton(
            folderButton,
            symbol: "folder.badge.plus",
            title: nil,
            toolTip: "New Folder",
            action: #selector(createFolder)
        )
        configureButton(
            rescanButton,
            symbol: "arrow.clockwise",
            title: nil,
            toolTip: "Rescan Applications",
            action: #selector(rescanApplications)
        )
        configureButton(
            closeButton,
            symbol: "xmark",
            title: nil,
            toolTip: "Close",
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
        action: Selector
    ) {
        button.target = self
        button.action = action
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
        editButton.toolTip = store.isEditing ? "Done Editing" : "Edit"
        rescanButton.isEnabled = store.contentState != .refreshing
        rescanButton.toolTip = store.contentState == .refreshing
            ? "Refreshing Applications"
            : "Rescan Applications"
    }

    private func updateStatus() {
        if let message = store.statusMessage {
            statusLabel.stringValue = message
            statusLabel.isHidden = false
            return
        }

        switch store.contentState {
        case .empty:
            statusLabel.stringValue = "No applications found. Use Rescan Applications to try again."
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
        let menu = NSMenu()
        menu.addItem(menuItem("Custom", action: #selector(setCustomSort), state: store.sortMode == .custom))
        menu.addItem(menuItem("A-Z", action: #selector(setNameSort), state: store.sortMode == .name))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sortButton.bounds.height + 4), in: sortButton)
    }

    @objc private func showLayoutMenu() {
        let menu = NSMenu()
        let countItem = NSMenuItem(title: "\(store.gridLayout.itemsPerPage) apps per page", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        menu.addItem(countItem)
        menu.addItem(.separator())

        let rowsItem = NSMenuItem(title: "Rows", action: nil, keyEquivalent: "")
        let rowsMenu = NSMenu()
        for rows in LauncherGridLayout.allowedRows {
            let item = NSMenuItem(title: "\(rows) rows", action: #selector(setRows(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = rows
            item.state = rows == store.gridLayout.rows ? .on : .off
            rowsMenu.addItem(item)
        }
        rowsItem.submenu = rowsMenu
        menu.addItem(rowsItem)

        let columnsItem = NSMenuItem(title: "Columns", action: nil, keyEquivalent: "")
        let columnsMenu = NSMenu()
        for columns in LauncherGridLayout.allowedColumns {
            let item = NSMenuItem(title: "\(columns) columns", action: #selector(setColumns(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = columns
            item.state = columns == store.gridLayout.columns ? .on : .off
            columnsMenu.addItem(item)
        }
        columnsItem.submenu = columnsMenu
        menu.addItem(columnsItem)
        menu.addItem(.separator())
        let reset = NSMenuItem(title: "Default 5 x 7", action: #selector(resetLayout), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: layoutButton.bounds.height + 4), in: layoutButton)
    }

    @objc private func showFilterMenu() {
        let menu = NSMenu()
        menu.addItem(menuItem("Visible Apps", action: #selector(showVisibleAppsOnly), state: store.appFilterMode == .visibleOnly))
        menu.addItem(menuItem("All Apps", action: #selector(showAllApps), state: store.appFilterMode == .all))
        menu.addItem(menuItem("Hidden Apps", action: #selector(showHiddenAppsOnly), state: store.appFilterMode == .hiddenOnly))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: filterButton.bounds.height + 4), in: filterButton)
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
        store.toggleEditing()
    }

    @objc private func createFolder() {
        showNamePrompt(title: "New Folder", initialValue: "") { [weak self] name in
            self?.store.createFolder(named: name)
        }
    }

    @objc private func rescanApplications() {
        store.requestRefresh()
    }

    @objc private func closeLauncher() {
        onClose()
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
        alert.addButton(withTitle: title == "New Folder" ? "Create" : "Rename")
        alert.addButton(withTitle: "Cancel")

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
            self?.onClose()
        }
        overlay.onRename = { [weak self] folder in
            self?.showNamePrompt(title: "Rename Folder", initialValue: folder.name) { name in
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
}

extension LauncherRootView: LauncherPagerDelegate {
    func pager(_ pager: LauncherPagerView, open tile: LauncherTile) {
        LumaEventLog.shared.write(
            "open.root",
            "tile=\(tile.id) title=\(tile.title) kind=\(tile.app == nil ? "folder" : "app")"
        )
        switch tile.kind {
        case let .app(app):
            store.launchApp(app)
            onClose()
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
            let open = ClosureMenuItem(title: "Open") { [weak self] in
                self?.store.launchApp(app)
                self?.onClose()
            }
            menu.addItem(open)
            menu.addItem(ClosureMenuItem(title: "Show in Finder") { [weak self] in
                self?.store.revealInFinder(app)
            })
            menu.addItem(ClosureMenuItem(title: store.isAppHidden(app.id) ? "Unhide App" : "Hide App") { [weak self] in
                guard let self else { return }
                self.store.setHidden(!self.store.isAppHidden(app.id), for: app.id)
            })

            let foldersItem = NSMenuItem(title: "Move to Folder", action: nil, keyEquivalent: "")
            let foldersMenu = NSMenu()
            for folder in store.folders {
                foldersMenu.addItem(ClosureMenuItem(title: folder.name) { [weak self] in
                    self?.store.addApp(app.id, to: folder.id)
                })
            }
            if !store.folders.isEmpty {
                foldersMenu.addItem(.separator())
            }
            foldersMenu.addItem(ClosureMenuItem(title: "New Folder") { [weak self] in
                self?.store.createFolder(containing: [app.id])
            })
            foldersItem.submenu = foldersMenu
            menu.addItem(foldersItem)
        case let .folder(folder, _):
            menu.addItem(ClosureMenuItem(title: "Open") { [weak self] in
                self?.showFolder(folder)
            })
            menu.addItem(ClosureMenuItem(title: "Rename") { [weak self] in
                self?.showNamePrompt(title: "Rename Folder", initialValue: folder.name) { name in
                    self?.store.renameFolder(id: folder.id, to: name)
                }
            })
            menu.addItem(ClosureMenuItem(title: "Delete Folder") { [weak self] in
                self?.store.deleteFolder(id: folder.id)
            })
        }
        return menu
    }
}

/// 将单行搜索文字垂直居中，并为搜索图标保留内边距的 Cell。
final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    private let textLayoutManager = NSLayoutManager()
    private let leadingInset: CGFloat = 40
    private let trailingInset: CGFloat = 8

    private func centeredTextRect(in bounds: NSRect) -> NSRect {
        guard let font else {
            return bounds
        }

        let lineHeight = ceil(textLayoutManager.defaultLineHeight(for: font))
        return NSRect(
            x: bounds.minX + leadingInset,
            y: floor(bounds.midY - lineHeight / 2),
            width: max(0, bounds.width - leadingInset - trailingInset),
            height: lineHeight
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredTextRect(in: super.titleRect(forBounds: rect))
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredTextRect(in: super.drawingRect(forBounds: rect))
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: centeredTextRect(in: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: centeredTextRect(in: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }
}

/// 在全屏 Panel 中支持首次点击直接获取焦点的搜索框。
final class SearchTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

/// `LauncherPagerView` 向根组合视图发送操作意图的边界协议。
@MainActor
protocol LauncherPagerDelegate: AnyObject {
    func pager(_ pager: LauncherPagerView, open tile: LauncherTile)
    func pagerDidRequestEditing(_ pager: LauncherPagerView)
    func pager(_ pager: LauncherPagerView, contextMenuFor tile: LauncherTile) -> NSMenu
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
    private var activeTileViews: [LauncherTileView] = []
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
            return self
        }

        if let tileView = interactiveTile(at: point, from: self) {
            if NSApp.currentEvent?.type == .leftMouseDown {
                let tilePoint = tileView.convert(point, from: self)
                LumaEventLog.shared.write(
                    "hit",
                    "page=\(store.pageIndex) tile=\(tileView.tileID) title=\(tileView.tile.title) "
                        + "pagerPoint=\(point) tilePoint=\(tilePoint) "
                        + "tileFrame=\(tileView.frame) contentOrigin=\(contentView.frame.origin)"
                )
            }
            return tileView
        }

        if NSApp.currentEvent?.type == .leftMouseDown {
            LumaEventLog.shared.write(
                "hit.none",
                "page=\(store.pageIndex) pagerPoint=\(point) "
                    + "contentOrigin=\(contentView.frame.origin)"
            )
        }
        return nil
    }

    /// 根据 Store 状态协调 Tile 视图，并可选地对差异执行动画。
    ///
    /// - Parameter animated: 是否为新增、删除和位置变化执行动画。
    func reload(animated: Bool) {
        replicaRefreshWorkItem?.cancel()
        replicaRefreshWorkItem = nil
        if animated {
            suspendInteraction(for: 0.22)
            setPageRasterizationEnabled(false)
            performReload(animated: true, refreshReplicas: false, retargetRunningAnimations: true)
            scheduleRenderStabilization(after: 0.24)
        } else {
            setPageRasterizationEnabled(true)
            performReload(animated: false, refreshReplicas: true, retargetRunningAnimations: false)
        }
    }

    /// 使用适合快速变化搜索结果的动画协调路径。
    func reloadSearchResults() {
        replicaRefreshWorkItem?.cancel()
        suspendInteraction(for: 0.18)
        setPageRasterizationEnabled(false)
        performReload(animated: true, refreshReplicas: false, retargetRunningAnimations: true)
        scheduleRenderStabilization(after: 0.20)
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
        var orderedActiveViews: [LauncherTileView] = []

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
            orderedActiveViews.append(view)
        }
        activeTileViews = orderedActiveViews

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
    }

    private func snapshot(of view: NSView) -> NSImage? {
        guard view.bounds.width > 0,
              view.bounds.height > 0,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }

        view.cacheDisplay(in: view.bounds, to: representation)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(representation)
        return image
    }

    private func tile(atDraggingLocation location: NSPoint) -> LauncherTileView? {
        interactiveTile(at: location, from: nil)
    }

    /// 通过真实 AppKit 视图层级解析坐标，避免手动拼接翻转坐标导致串位。
    ///
    /// - Parameters:
    ///   - point: 待命中的坐标点。
    ///   - sourceView: 坐标所属视图；为 `nil` 时表示窗口坐标。
    /// - Returns: 实际命中的可交互 Tile；没有命中时返回 `nil`。
    private func interactiveTile(at point: NSPoint, from sourceView: NSView?) -> LauncherTileView? {
        guard let currentPage = pageViews[store.pageIndex] else {
            return nil
        }

        return activeTileViews.reversed().first { view in
            guard view.superview === currentPage,
                  activeTileIDs.contains(view.tileID),
                  view.alphaValue > 0.05 else {
                return false
            }

            let tilePoint = view.convert(point, from: sourceView)
            return view.bounds.contains(tilePoint) && view.hitTest(tilePoint) === view
        }
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
        defer {
            dropTargetID = nil
            store.endDraggingTile(commit: true)
        }

        guard let draggedID = sender.draggingPasteboard.string(forType: .string) else {
            return false
        }

        if let target = tile(atDraggingLocation: sender.draggingLocation),
           let folder = target.tile.folder,
           draggedID.hasPrefix("app:") {
            store.addApp(draggedID, to: folder.id)
        }
        return true
    }
}

extension LauncherPagerView: LauncherTileViewDelegate {
    func tileView(_ view: LauncherTileView, didRequestOpen tile: LauncherTile) {
        LumaEventLog.shared.write(
            "open.delegate",
            "pressed=\(tile.id) pressedTitle=\(tile.title) "
                + "viewNow=\(view.tileID) viewTitle=\(view.tile.title)"
        )
        delegate?.pager(self, open: tile)
    }

    func tileViewDidRequestEditing(_ view: LauncherTileView) {
        delegate?.pagerDidRequestEditing(self)
    }

    func tileViewDidBeginDragging(_ view: LauncherTileView) {
        store.beginDraggingTile(view.tileID)
    }

    func tileViewDidEndDragging(_ view: LauncherTileView) {
        dropTargetID = nil
        store.endDraggingTile(commit: false)
    }

    func tileView(_ view: LauncherTileView, draggingUpdatedWith draggedID: String) -> NSDragOperation {
        guard store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        updateDropTarget(draggedID: draggedID, target: view)
        return .move
    }

    func tileView(_ view: LauncherTileView, performDropWith draggedID: String) -> Bool {
        defer {
            dropTargetID = nil
            store.endDraggingTile(commit: true)
        }

        if let folder = view.tile.folder, draggedID.hasPrefix("app:") {
            store.addApp(draggedID, to: folder.id)
        } else {
            updateDropTarget(draggedID: draggedID, target: view)
        }
        return true
    }

    func tileView(_ view: LauncherTileView, contextMenuFor tile: LauncherTile) -> NSMenu {
        delegate?.pager(self, contextMenuFor: tile) ?? NSMenu()
    }
}

/// 单个 Tile 视图向所属 Pager 发送操作意图的边界协议。
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
        iconHitFrame.contains(point) ? self : nil
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
        let iconFrameInWindow = convert(iconHitFrame, to: nil)
        LumaEventLog.shared.write(
            "click.down",
            "tile=\(tile.id) title=\(tile.title) windowPoint=\(event.locationInWindow) "
                + "iconFrame=\(iconFrameInWindow) editing=\(isEditing)"
        )
        if isEditing {
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.longPressTriggered = true
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
        guard let pressedTile, pressedTile.id == tile.id else {
            LumaEventLog.shared.write(
                "click.cancel",
                "reason=tileChanged pressed=\(pressedTile?.id ?? "nil") current=\(tile.id)"
            )
            return
        }

        LumaEventLog.shared.write(
            "click.up",
            "tile=\(pressedTile.id) title=\(pressedTile.title) currentView=\(tile.id) "
                + "windowPoint=\(event.locationInWindow)"
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
        return delegate?.tileView(self, draggingUpdatedWith: draggedID) ?? []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.string(forType: .string) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let draggedID = sender.draggingPasteboard.string(forType: .string) else {
            return false
        }
        return delegate?.tileView(self, performDropWith: draggedID) ?? false
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
        delegate?.tileViewDidEndDragging(self)
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
            editBadge.isHidden = !isEditing
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
        editBadge.isHidden = !editing
        updateAppearance(animated: true)
    }

    private var iconHitFrame: NSRect {
        iconView.frame.insetBy(dx: -3, dy: -3)
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
}

/// 以模态浮层形式展示并管理一个文件夹内的应用。
@MainActor
final class FolderOverlayView: NSView {
    let folderID: String
    var onClose: (() -> Void)?
    var onLaunch: ((LauncherAppInfo) -> Void)?
    var onRename: ((LauncherFolder) -> Void)?

    private let store: LauncherStore
    private var folder: LauncherFolder
    private let panel = NSVisualEffectView()
    private let titleButton = NSButton()
    private let closeButton = NSButton()
    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let emptyStateLabel = NSTextField(labelWithString: "No apps in this folder")
    private var appViews: [FolderAppTileView] = []

    override var isFlipped: Bool { true }

    init(frame: NSRect, folder: LauncherFolder, store: LauncherStore) {
        folderID = folder.id
        self.folder = folder
        self.store = store
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor

        panel.material = .hudWindow
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 32
        panel.layer?.cornerCurve = .continuous
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        addSubview(panel)

        titleButton.isBordered = false
        titleButton.font = .systemFont(ofSize: 25, weight: .semibold)
        titleButton.contentTintColor = .white
        titleButton.target = self
        titleButton.action = #selector(renameFolder)
        titleButton.setAccessibilityLabel("Rename \(folder.name)")
        panel.addSubview(titleButton)

        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.contentTintColor = .white.withAlphaComponent(0.82)
        closeButton.target = self
        closeButton.action = #selector(closeOverlay)
        panel.addSubview(closeButton)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = documentView
        panel.addSubview(scrollView)

        emptyStateLabel.font = .systemFont(ofSize: 16, weight: .medium)
        emptyStateLabel.textColor = .white.withAlphaComponent(0.60)
        emptyStateLabel.alignment = .center
        emptyStateLabel.isHidden = true
        panel.addSubview(emptyStateLabel)
        reloadApps()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let panelSize = NSSize(width: 650, height: min(520, max(420, bounds.height - 180)))
        panel.frame = NSRect(
            x: floor((bounds.width - panelSize.width) / 2),
            y: floor((bounds.height - panelSize.height) / 2),
            width: panelSize.width,
            height: panelSize.height
        )
        titleButton.frame = NSRect(x: 26, y: 20, width: panel.bounds.width - 100, height: 38)
        closeButton.frame = NSRect(x: panel.bounds.width - 58, y: 20, width: 34, height: 34)
        scrollView.frame = NSRect(x: 22, y: 74, width: panel.bounds.width - 44, height: panel.bounds.height - 96)
        emptyStateLabel.frame = NSRect(
            x: 48,
            y: floor(panel.bounds.midY - 12),
            width: panel.bounds.width - 96,
            height: 24
        )
        layoutApps()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !panel.frame.contains(point) {
            onClose?()
        }
    }

    func update(folder: LauncherFolder) {
        self.folder = folder
        reloadApps()
    }

    /// 根据 Store 派生的文件夹成员重建应用 Tile。
    private func reloadApps() {
        titleButton.title = folder.name
        appViews.forEach { $0.removeFromSuperview() }
        appViews = store.apps(in: folder).map { app in
            let view = FolderAppTileView(app: app, store: store)
            view.onOpen = { [weak self] app in self?.onLaunch?(app) }
            view.onRemove = { [weak self] app in
                guard let self else { return }
                self.store.removeApp(app.id, from: self.folder.id)
            }
            view.onToggleHidden = { [weak self] app in
                guard let self else { return }
                self.store.setHidden(!self.store.isAppHidden(app.id), for: app.id)
            }
            documentView.addSubview(view)
            return view
        }
        emptyStateLabel.isHidden = !appViews.isEmpty
        needsLayout = true
    }

    private func layoutApps() {
        let columns = 4
        let tileWidth: CGFloat = 136
        let tileHeight: CGFloat = 132
        let gap: CGFloat = 10
        let contentWidth = scrollView.contentSize.width
        let gridWidth = CGFloat(columns) * tileWidth + CGFloat(columns - 1) * gap
        let leading = max(0, floor((contentWidth - gridWidth) / 2))

        for (index, view) in appViews.enumerated() {
            let row = index / columns
            let column = index % columns
            view.frame = NSRect(
                x: leading + CGFloat(column) * (tileWidth + gap),
                y: CGFloat(row) * (tileHeight + 10),
                width: tileWidth,
                height: tileHeight
            )
        }
        let rows = max(1, Int(ceil(Double(appViews.count) / Double(columns))))
        documentView.frame = NSRect(
            x: 0,
            y: 0,
            width: contentWidth,
            height: CGFloat(rows) * (tileHeight + 10)
        )
    }

    @objc private func closeOverlay() {
        onClose?()
    }

    @objc private func renameFolder() {
        onRename?(folder)
    }
}

/// 仅在文件夹浮层中使用的紧凑应用 Tile。
@MainActor
final class FolderAppTileView: NSView {
    var onOpen: ((LauncherAppInfo) -> Void)?
    var onRemove: ((LauncherAppInfo) -> Void)?
    var onToggleHidden: ((LauncherAppInfo) -> Void)?

    private let app: LauncherAppInfo
    private let store: LauncherStore
    private let iconButton = NSButton()
    private let label = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    init(app: LauncherAppInfo, store: LauncherStore) {
        self.app = app
        self.store = store
        super.init(frame: .zero)

        iconButton.isBordered = false
        iconButton.image = store.appIcon(for: app, size: 82)
        iconButton.imageScaling = .scaleProportionallyUpOrDown
        iconButton.target = self
        iconButton.action = #selector(openApp)
        addSubview(iconButton)

        label.stringValue = app.title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        iconButton.frame = NSRect(x: floor((bounds.width - 82) / 2), y: 4, width: 82, height: 82)
        label.frame = NSRect(x: 2, y: 94, width: bounds.width - 4, height: 34)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: store.isAppHidden(app.id) ? "Unhide App" : "Hide App") { [weak self] in
            guard let self else { return }
            self.onToggleHidden?(self.app)
        })
        menu.addItem(ClosureMenuItem(title: "Remove from Folder") { [weak self] in
            guard let self else { return }
            self.onRemove?(self.app)
        })
        return menu
    }

    @objc private func openApp() {
        onOpen?(app)
    }
}

/// 使用 Core Animation Layer 承载的启动器色调渐变视图。
final class GradientBackgroundView: NSView {
    var colors: [NSColor] = [] {
        didSet {
            gradientLayer.colors = colors.map(\.cgColor)
        }
    }

    private let gradientLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = gradientLayer
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 显式绘制 Hover 和按下状态的自定义顶部控件。
final class HeaderButton: NSControl {
    private var trackingAreaToken: NSTrackingArea?
    private var hovering = false
    private var pressed = false
    private let hoverShape = CAShapeLayer()
    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    var image: NSImage? {
        didSet {
            symbolView.image = image
            needsLayout = true
        }
    }

    var title = "" {
        didSet {
            titleLabel.stringValue = title
            needsLayout = true
        }
    }

    var textFont: NSFont = .systemFont(ofSize: 13.5, weight: .semibold) {
        didSet {
            titleLabel.font = textFont
            needsLayout = true
        }
    }

    var contentTintColor: NSColor = .white {
        didSet {
            updateForegroundColor()
        }
    }

    override var isEnabled: Bool {
        didSet {
            updateForegroundColor()
            updateBackground(animated: false)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureHoverShape()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureHoverShape() {
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        hoverShape.fillColor = NSColor.white.withAlphaComponent(0.018).cgColor
        hoverShape.strokeColor = NSColor.clear.cgColor
        hoverShape.lineWidth = 1
        layer?.insertSublayer(hoverShape, at: 0)

        symbolView.imageScaling = .scaleProportionallyDown
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        addSubview(symbolView)

        titleLabel.font = textFont
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)
        updateForegroundColor()
    }

    override func layout() {
        super.layout()
        hoverShape.frame = bounds
        let hoverRect = bounds.insetBy(dx: 1.5, dy: 3)
        hoverShape.path = CGPath(
            roundedRect: hoverRect,
            cornerWidth: hoverRect.height / 2,
            cornerHeight: hoverRect.height / 2,
            transform: nil
        )

        let iconSize: CGFloat = image == nil ? 0 : 18
        let spacing: CGFloat = image == nil || title.isEmpty ? 0 : 10
        let measuredTitleWidth = title.isEmpty
            ? CGFloat.zero
            : ceil((title as NSString).size(withAttributes: [.font: textFont]).width)
        let maxTitleWidth = max(0, bounds.width - iconSize - spacing - 24)
        let titleWidth = min(measuredTitleWidth, maxTitleWidth)
        let groupWidth = iconSize + spacing + titleWidth
        let startX = max(8, floor((bounds.width - groupWidth) / 2))
        let centerY = bounds.midY

        symbolView.isHidden = image == nil
        titleLabel.isHidden = title.isEmpty
        if image != nil {
            symbolView.frame = NSRect(
                x: startX,
                y: floor(centerY - iconSize / 2),
                width: iconSize,
                height: iconSize
            )
        }
        titleLabel.frame = NSRect(
            x: startX + iconSize + spacing,
            y: floor(centerY - 10),
            width: titleWidth,
            height: 20
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaToken {
            removeTrackingArea(trackingAreaToken)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(tracking)
        trackingAreaToken = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        updateBackground(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        updateBackground(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else { return }

        pressed = true
        updateBackground(animated: false)

        while let trackingEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let localPoint = convert(trackingEvent.locationInWindow, from: nil)
            let isInside = bounds.contains(localPoint)

            if trackingEvent.type == .leftMouseDragged {
                if pressed != isInside {
                    pressed = isInside
                    updateBackground(animated: false)
                }
                continue
            }

            pressed = false
            updateBackground(animated: true)
            if isInside, let action {
                LumaEventLog.shared.write("header.action", toolTip ?? NSStringFromSelector(action))
                NSApp.sendAction(action, to: target, from: self)
            }
            return
        }

        pressed = false
        updateBackground(animated: true)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func updateForegroundColor() {
        let alpha: CGFloat = isEnabled ? 1 : 0.45
        let color = contentTintColor.withAlphaComponent(contentTintColor.alphaComponent * alpha)
        symbolView.contentTintColor = color
        titleLabel.textColor = color
    }

    /// 只动画 Layer 颜色，保持控件布局和命中测试稳定。
    ///
    /// - Parameter animated: 是否执行颜色过渡动画。
    private func updateBackground(animated: Bool) {
        let backgroundColor: NSColor
        let borderColor: NSColor
        if pressed {
            backgroundColor = .white.withAlphaComponent(0.16)
            borderColor = .white.withAlphaComponent(0.20)
        } else if hovering && isEnabled {
            backgroundColor = .white.withAlphaComponent(0.10)
            borderColor = .white.withAlphaComponent(0.14)
        } else {
            backgroundColor = .white.withAlphaComponent(0.018)
            borderColor = .clear
        }

        let background = backgroundColor.cgColor
        let border = borderColor.cgColor
        guard animated else {
            hoverShape.fillColor = background
            hoverShape.strokeColor = border
            return
        }

        let backgroundAnimation = CABasicAnimation(keyPath: "fillColor")
        backgroundAnimation.fromValue = hoverShape.presentation()?.fillColor ?? hoverShape.fillColor
        backgroundAnimation.toValue = background
        backgroundAnimation.duration = 0.16
        backgroundAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let borderAnimation = CABasicAnimation(keyPath: "strokeColor")
        borderAnimation.fromValue = hoverShape.presentation()?.strokeColor ?? hoverShape.strokeColor
        borderAnimation.toValue = border
        borderAnimation.duration = 0.16
        borderAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        hoverShape.fillColor = background
        hoverShape.strokeColor = border
        hoverShape.add(backgroundAnimation, forKey: "hoverBackground")
        hoverShape.add(borderAnimation, forKey: "hoverBorder")
    }
}

/// 使用左上角坐标系的 AppKit 工具容器。
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 绘制分页指示器，并将点击转换为页码选择意图。
final class PageDotsView: NSView {
    var pageCount = 1 {
        didSet { needsDisplay = true }
    }
    var currentPage = 0 {
        didSet { needsDisplay = true }
    }
    var onSelect: ((Int) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let count = max(1, pageCount)
        let spacing: CGFloat = 14
        let totalWidth = CGFloat(count - 1) * spacing + 8
        let startX = floor((bounds.width - totalWidth) / 2)
        for index in 0..<count {
            let size: CGFloat = index == currentPage ? 8 : 6
            let rect = NSRect(
                x: startX + CGFloat(index) * spacing,
                y: floor((bounds.height - size) / 2),
                width: size,
                height: size
            )
            (index == currentPage
                ? NSColor.white.withAlphaComponent(0.92)
                : NSColor.white.withAlphaComponent(0.34)
            ).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let count = max(1, pageCount)
        let spacing: CGFloat = 14
        let totalWidth = CGFloat(count - 1) * spacing + 8
        let startX = floor((bounds.width - totalWidth) / 2)
        let point = convert(event.locationInWindow, from: nil)
        let index = Int(round((point.x - startX) / spacing))
        guard index >= 0, index < count else { return }
        onSelect?(index)
    }
}

/// 持有闭包动作的 `NSMenuItem` 子类。
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    /// 创建闭包驱动的菜单项。
    ///
    /// - Parameters:
    ///   - title: 菜单项显示文本。
    ///   - handler: 用户选择菜单项后执行的动作。
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        handler()
    }
}

/// 使用最多四个应用图标生成组合文件夹图标。
enum FolderIconRenderer {
    /// 生成文件夹组合图标。
    ///
    /// - Parameters:
    ///   - apps: 用于组成文件夹预览的应用，最多读取前四个。
    ///   - store: 用于获取应用图标缓存的业务 Store。
    ///   - size: 输出图像的宽高尺寸。
    /// - Returns: 渲染完成的文件夹图标。
    @MainActor
    static func image(apps: [LauncherAppInfo], store: LauncherStore, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: size * 0.22, yRadius: size * 0.22)
        border.lineWidth = 1
        border.stroke()

        let gap = size * 0.07
        let inset = size * 0.13
        let cell = (size - inset * 2 - gap) / 2
        for index in 0..<4 {
            let row = index / 2
            let column = index % 2
            let cellRect = NSRect(
                x: inset + CGFloat(column) * (cell + gap),
                y: size - inset - cell - CGFloat(row) * (cell + gap),
                width: cell,
                height: cell
            )
            if index < apps.count {
                store.appIcon(for: apps[index], size: cell).draw(in: cellRect)
            } else {
                NSColor.white.withAlphaComponent(0.09).setFill()
                NSBezierPath(roundedRect: cellRect, xRadius: cell * 0.18, yRadius: cell * 0.18).fill()
            }
        }
        return image
    }
}

/// 根据 Pager 尺寸和已校验网格布局计算出的 Tile 几何参数。
struct LauncherGridMetrics {
    let columns: Int
    let rows: Int
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let iconSize: CGFloat
    let titleHeight: CGFloat
    let iconTitleSpacing: CGFloat
    let tileVerticalPadding: CGFloat
    let rowSpacing: CGFloat
    let columnSpacing: CGFloat
    let leadingInset: CGFloat

    /// 根据可用区域和网格配置计算 Tile 几何参数。
    ///
    /// - Parameters:
    ///   - size: Pager 中可用于网格内容的尺寸。
    ///   - layout: 已校验的行列布局。
    init(size: CGSize, layout: LauncherGridLayout) {
        columns = layout.columns
        rows = layout.rows
        rowSpacing = 10
        columnSpacing = 14

        let availableWidth = max(360, size.width)
        let availableHeight = max(260, size.height)
        let rawTileWidth = (availableWidth - CGFloat(columns - 1) * columnSpacing) / CGFloat(columns)
        let rawTileHeight = (availableHeight - CGFloat(rows - 1) * rowSpacing) / CGFloat(rows)

        tileWidth = floor(min(260, max(112, rawTileWidth)))
        tileHeight = floor(min(166, max(88, rawTileHeight)))
        iconSize = floor(min(108, max(46, min(tileWidth - 34, tileHeight - 48))))
        titleHeight = floor(min(34, max(22, tileHeight - iconSize - 24)))
        iconTitleSpacing = min(10, max(4, tileHeight - iconSize - titleHeight - 16))
        tileVerticalPadding = min(10, max(6, (tileHeight - iconSize - titleHeight - iconTitleSpacing) / 2))

        let gridWidth = CGFloat(columns) * tileWidth + CGFloat(columns - 1) * columnSpacing
        leadingInset = max(0, floor((availableWidth - gridWidth) / 2))
    }

    var itemsPerPage: Int {
        rows * columns
    }
}
