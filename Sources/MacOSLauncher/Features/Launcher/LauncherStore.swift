import AppKit
import Foundation

/// 描述 UI 哪一部分需要更新的粗粒度通知。
///
/// 调用方向：`LauncherStore` 发出 -> `LauncherRootView` 消费。
enum LauncherStoreChange {
    case content(animated: Bool)
    case state
    case search
    case pageDrag
    case pageSettled(previousIndex: Int, previousOffset: CGFloat)
    case editing
    case presentation
}

/// 在主线程管理应用、文件夹、排序、搜索和分页业务状态。
///
/// 调用方向：
/// - `AppLifecycleCoordinator` 输入偏好、缓存和扫描结果。
/// - View 输入搜索、分页、文件夹和拖拽预览等用户意图。
/// - Store 发出 `LauncherStoreChange`，View 读取派生状态后重绘。
/// - 文件扫描和 AppKit 窗口控制明确放在此类型之外。
@MainActor
final class LauncherStore {
    private(set) var apps: [LauncherAppInfo] = []
    private(set) var folders: [LauncherFolder] = []
    private(set) var tileOrder: [String] = []
    private(set) var searchText = ""
    private(set) var pageIndex = 0
    private(set) var pageDragOffset: CGFloat = 0
    private(set) var isEditing = false
    private(set) var draggedTileID: String?
    private(set) var sortMode: SortMode = .custom
    private(set) var gridLayout: LauncherGridLayout = .default
    private(set) var hiddenAppIDs = Set<String>()
    private(set) var appFilterMode: AppFilterMode = .visibleOnly
    private(set) var contentState: LauncherContentState = .ready
    private(set) var lastScannedAt: Date?
    private(set) var statusMessage: String?

    var onChange: ((LauncherStoreChange) -> Void)?
    var onRefreshRequested: (() -> Void)?

    private let preferencesStore: any PreferencesStoring
    private let applicationLauncher: any ApplicationLaunching
    private var iconCache: [String: NSImage] = [:]
    private var pageDragRawOffset: CGFloat = 0
    private var tileOrderBeforeDrag: [String]?
    private var dragPreviewChanged = false

    /// 创建启动器业务状态。
    ///
    /// - Parameters:
    ///   - preferencesStore: 用于异步保存用户偏好的服务。
    ///   - applicationLauncher: 用于启动应用和 Finder 定位的服务。
    init(
        preferencesStore: any PreferencesStoring,
        applicationLauncher: any ApplicationLaunching
    ) {
        self.preferencesStore = preferencesStore
        self.applicationLauncher = applicationLauncher
    }

    /// 经过搜索、筛选、文件夹归属和排序后，当前可以展示的 Tile。
    var visibleTiles: [LauncherTile] {
        let query = normalized(searchText)
        if query.isEmpty {
            return orderedTiles()
        }

        let matchingApps = apps
            .filter { app in
                isAppVisibleInCurrentFilter(app)
                    && (
                        normalized(app.title).contains(query)
                            || normalized(app.bundleIdentifier ?? "").contains(query)
                    )
            }
            .sorted(by: sortByTitle)
            .map(makeAppTile)

        let matchingFolders = folders
            .filter { folder in
                normalized(folder.name).contains(query) && shouldShowFolder(folder)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .map(makeFolderTile)

        return matchingApps + matchingFolders
    }

    /// 当前可见 Tile 在现有网格布局下所需的页数。
    var pageCount: Int {
        max(1, Int(ceil(Double(visibleTiles.count) / Double(gridLayout.itemsPerPage))))
    }

    // MARK: - 生命周期输入

    /// 应用已持久化的用户配置，不触发磁盘读写。
    ///
    /// 由 `AppLifecycleCoordinator.restoreStateAndRefresh` 调用。
    ///
    /// - Parameter preferences: 从本地读取的完整用户偏好。
    func applyPreferences(_ preferences: LauncherPreferences) {
        sortMode = preferences.sortMode
        tileOrder = preferences.tileOrder
        folders = preferences.folders
        gridLayout = preferences.gridLayout
        hiddenAppIDs = Set(preferences.hiddenAppIDs)
        appFilterMode = preferences.appFilterMode
        if !apps.isEmpty {
            reconcileAfterAppScan(persist: false)
        }
        onChange?(.content(animated: false))
    }

    /// 在后台扫描前立即应用缓存应用列表。
    ///
    /// 由 `AppLifecycleCoordinator.restoreStateAndRefresh` 调用。
    ///
    /// - Parameter cache: 最近一次成功扫描的应用缓存。
    func applyCachedApplications(_ cache: ApplicationCache) {
        apps = cache.applications
        lastScannedAt = cache.lastScannedAt
        let validIconIDs = Set(apps.map(\.id))
        iconCache = iconCache.filter { validIconIDs.contains($0.key) }
        reconcileAfterAppScan(persist: false)
        contentState = apps.isEmpty ? .empty : .ready
        onChange?(.content(animated: false))
    }

    /// 进入非阻塞刷新状态，同时保留已有应用内容。
    ///
    /// 由协调器在启动扫描任务前调用。
    func beginRefreshing() {
        contentState = .refreshing
        statusMessage = apps.isEmpty ? "Finding applications…" : "Refreshing…"
        onChange?(.state)
    }

    /// 将成功扫描结果与文件夹、顺序、筛选和分页状态合并。
    ///
    /// 协调器尝试保存缓存后调用。
    ///
    /// - Parameters:
    ///   - applications: 最新扫描到的应用列表。
    ///   - scannedAt: 本次扫描完成时间。
    func finishRefreshing(with applications: [LauncherAppInfo], scannedAt: Date) {
        apps = applications
        lastScannedAt = scannedAt
        let validIconIDs = Set(apps.map(\.id))
        iconCache = iconCache.filter { validIconIDs.contains($0.key) }
        reconcileAfterAppScan()
        contentState = apps.isEmpty ? .empty : .ready
        statusMessage = nil
        onChange?(.content(animated: false))
    }

    /// 无可用内容时展示错误；存在缓存时保留内容并显示轻量提示。
    ///
    /// - Parameter error: 可恢复的刷新错误。
    func failRefreshing(_ error: LauncherRecoverableError) {
        contentState = apps.isEmpty ? .failed(error) : .ready
        statusMessage = apps.isEmpty ? error.message : "Refresh failed. Showing cached apps."
        onChange?(.state)
    }

    /// 将偏好恢复信息显示为轻量状态消息。
    ///
    /// - Parameter message: 需要显示给用户的恢复说明。
    func reportPreferencesRecovery(_ message: String) {
        statusMessage = message
        onChange?(.state)
    }

    /// 向上发送刷新意图；Store 本身不执行文件系统扫描。
    ///
    /// 调用方向：顶部按钮/菜单 -> Store -> `AppLifecycleCoordinator`。
    func requestRefresh() {
        onRefreshRequested?()
    }

    // MARK: - 用户偏好

    /// 修改排序模式、重置页码、保存偏好并请求动画重绘。
    ///
    /// - Parameter mode: 新的 Tile 排序模式。
    func setSortMode(_ mode: SortMode) {
        sortMode = mode
        pageIndex = 0
        savePreferences()
        onChange?(.content(animated: true))
    }

    /// 校验并保存新的网格布局。
    ///
    /// - Parameters:
    ///   - rows: 每页行数。
    ///   - columns: 每页列数。
    func setGridLayout(rows: Int, columns: Int) {
        gridLayout = LauncherGridLayout(rows: rows, columns: columns)
        pageIndex = 0
        savePreferences()
        onChange?(.content(animated: true))
    }

    func setGridRows(_ rows: Int) {
        setGridLayout(rows: rows, columns: gridLayout.columns)
    }

    func setGridColumns(_ columns: Int) {
        setGridLayout(rows: gridLayout.rows, columns: columns)
    }

    func resetGridLayout() {
        gridLayout = .default
        pageIndex = 0
        savePreferences()
        onChange?(.content(animated: true))
    }

    /// 修改参与派生 Tile 计算的隐藏状态筛选范围。
    ///
    /// - Parameter mode: 新的应用筛选模式。
    func setAppFilterMode(_ mode: AppFilterMode) {
        guard appFilterMode != mode else {
            return
        }

        appFilterMode = mode
        pageIndex = 0
        savePreferences()
        onChange?(.content(animated: true))
    }

    /// 修改单个应用的隐藏状态并保存偏好。
    ///
    /// - Parameters:
    ///   - hidden: `true` 表示隐藏，`false` 表示取消隐藏。
    ///   - appID: 目标应用标识。
    func setHidden(_ hidden: Bool, for appID: String) {
        guard app(withID: appID) != nil else {
            return
        }

        if hidden {
            hiddenAppIDs.insert(appID)
        } else {
            hiddenAppIDs.remove(appID)
        }

        pageIndex = 0
        savePreferences()
        onChange?(.content(animated: true))
    }

    /// 在内存中应用搜索词并重置页码，不执行磁盘写入。
    ///
    /// - Parameter value: 用户输入的搜索文本。
    func setSearchText(_ value: String) {
        guard searchText != value else {
            return
        }

        searchText = value
        pageIndex = 0
        pageDragRawOffset = 0
        pageDragOffset = 0
        onChange?(.search)
    }

    // MARK: - 展示与分页

    /// 启动器面板出现前重置搜索、页码、编辑和拖拽等临时状态。
    func prepareForPresentation() {
        searchText = ""
        pageIndex = 0
        pageDragRawOffset = 0
        pageDragOffset = 0
        isEditing = false
        draggedTileID = nil
        onChange?(.presentation)
    }

    /// 为键盘或分页圆点执行首尾循环翻页。
    ///
    /// - Parameter offset: 页码偏移量；正数向后，负数向前。
    func changePage(by offset: Int) {
        guard offset != 0, pageCount > 1 else {
            return
        }

        let previousIndex = pageIndex
        let previousOffset = pageDragOffset
        pageIndex = wrappedPageIndex(pageIndex + offset)
        pageDragRawOffset = 0
        pageDragOffset = 0
        onChange?(.pageSettled(previousIndex: previousIndex, previousOffset: previousOffset))
    }

    /// 以零累计位移开始交互式分页。
    ///
    /// 调用方向：`LauncherPanel.scrollWheel` -> Controller 回调 -> Store。
    func beginPageDrag() {
        pageDragRawOffset = 0
        pageDragOffset = 0
        onChange?(.pageDrag)
    }

    /// 累加并限制水平位移，使页面跟随手指移动。
    ///
    /// - Parameters:
    ///   - deltaX: 本次触控板事件的水平增量。
    ///   - pageWidth: 当前页面宽度，用于限制最大位移。
    func updatePageDrag(deltaX: CGFloat, pageWidth: CGFloat) {
        guard pageWidth > 0 else {
            return
        }

        pageDragRawOffset += deltaX
        pageDragOffset = min(max(pageDragRawOffset, -pageWidth), pageWidth)
        onChange?(.pageDrag)
    }

    /// 根据调优后的位移阈值提交或取消翻页。
    ///
    /// - Parameter pageWidth: 当前页面宽度，用于计算翻页阈值。
    func finishPageDrag(pageWidth: CGFloat) {
        guard pageWidth > 0 else {
            pageDragRawOffset = 0
            pageDragOffset = 0
            return
        }

        let previousIndex = pageIndex
        let previousOffset = pageDragOffset
        let threshold = min(145, pageWidth * 0.15)
        if pageDragRawOffset <= -threshold {
            pageIndex = wrappedPageIndex(pageIndex + 1)
        } else if pageDragRawOffset >= threshold {
            pageIndex = wrappedPageIndex(pageIndex - 1)
        }

        pageDragRawOffset = 0
        pageDragOffset = 0
        onChange?(.pageSettled(previousIndex: previousIndex, previousOffset: previousOffset))
    }

    private func wrappedPageIndex(_ index: Int) -> Int {
        guard pageCount > 0 else {
            return 0
        }
        return (index % pageCount + pageCount) % pageCount
    }

    // MARK: - 编辑与拖拽排序

    /// 响应顶部按钮切换编辑模式。
    func toggleEditing() {
        if isEditing {
            endEditing()
        } else {
            beginEditing()
        }
    }

    func beginEditing() {
        isEditing = true
        onChange?(.editing)
    }

    func endEditing() {
        draggedTileID = nil
        isEditing = false
        onChange?(.editing)
    }

    /// 保存拖拽前顺序，并进入自定义排序模式。
    ///
    /// 调用方向：Tile 拖拽源 -> Pager delegate -> Store。
    ///
    /// - Parameter tileID: 开始拖拽的 Tile 标识。
    func beginDraggingTile(_ tileID: String) {
        if sortMode != .custom {
            tileOrder = orderedTiles().map(\.id)
            sortMode = .custom
        }

        tileOrderBeforeDrag = tileOrder
        dragPreviewChanged = false
        draggedTileID = tileID
        isEditing = true
        onChange?(.editing)
    }

    /// 成功时只执行一次最终保存，取消时恢复拖拽前顺序。
    ///
    /// 悬停过程只调用 `previewMoveTile`；成功放下传 `true`，
    /// 取消或在无效位置结束传 `false`。
    ///
    /// - Parameter commit: 是否提交本次拖拽预览。
    func endDraggingTile(commit: Bool) {
        if commit {
            if dragPreviewChanged {
                savePreferences()
            }
        } else if let tileOrderBeforeDrag {
            tileOrder = tileOrderBeforeDrag
            onChange?(.content(animated: true))
        }

        tileOrderBeforeDrag = nil
        dragPreviewChanged = false
        draggedTileID = nil
        onChange?(.editing)
    }

    // MARK: - 应用操作

    /// 返回内存缓存的 Workspace 图标，供 Tile 和文件夹渲染。
    ///
    /// - Parameters:
    ///   - app: 目标应用。
    ///   - size: 期望图标尺寸；当前缓存按应用复用该图标。
    /// - Returns: 应用图标。
    func appIcon(for app: LauncherAppInfo, size _: CGFloat = 96) -> NSImage {
        if let cached = iconCache[app.id] {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: app.path)
        iconCache[app.id] = icon
        return icon
    }

    /// 将启动意图转发给注入的应用启动服务。
    ///
    /// - Parameter app: 需要启动的应用。
    func launchApp(_ app: LauncherAppInfo) {
        applicationLauncher.launch(app)
    }

    /// 将 Finder 定位意图转发给注入的应用启动服务。
    ///
    /// - Parameter app: 需要在 Finder 中显示的应用。
    func revealInFinder(_ app: LauncherAppInfo) {
        applicationLauncher.revealInFinder(app)
    }

    // MARK: - 文件夹变更

    /// 创建名称唯一的文件夹，并可选地将应用移入其中。
    ///
    /// - Parameters:
    ///   - name: 用户输入的文件夹名称；为空时使用默认名称。
    ///   - itemIDs: 创建后立即放入文件夹的应用标识。
    /// - Returns: 新创建的文件夹模型。
    @discardableResult
    func createFolder(named name: String? = nil, containing itemIDs: [String] = []) -> LauncherFolder {
        let validItemIDs = itemIDs.filter { app(withID: $0) != nil }
        let folder = LauncherFolder(
            id: UUID().uuidString,
            name: uniqueFolderName(name?.trimmedNonEmpty ?? "New Folder"),
            itemIDs: validItemIDs
        )

        removeAppsFromFolders(validItemIDs)
        folders.append(folder)
        tileOrder.removeAll { validItemIDs.contains($0) }
        tileOrder.append(folder.tileID)
        reconcileAfterAppScan()
        onChange?(.content(animated: true))
        return folder
    }

    /// 重命名文件夹，并保持忽略大小写后的名称唯一性。
    ///
    /// - Parameters:
    ///   - id: 文件夹标识。
    ///   - name: 新文件夹名称。
    func renameFolder(id: String, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            return
        }

        folders[index].name = uniqueFolderName(name.trimmedNonEmpty ?? folders[index].name, excluding: id)
        savePreferences()
        onChange?(.content(animated: true))
    }

    /// 删除文件夹；后续协调会将其中应用恢复为顶层 Tile。
    ///
    /// - Parameter id: 需要删除的文件夹标识。
    func deleteFolder(id: String) {
        guard let folder = folder(withID: id) else {
            return
        }

        folders.removeAll { $0.id == id }
        tileOrder.removeAll { $0 == folder.tileID }
        reconcileAfterAppScan()
        onChange?(.content(animated: true))
    }

    /// 将应用从原文件夹移动到目标文件夹。
    ///
    /// - Parameters:
    ///   - appID: 应用标识。
    ///   - folderID: 目标文件夹标识。
    func addApp(_ appID: String, to folderID: String) {
        guard app(withID: appID) != nil,
              let index = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }

        removeAppsFromFolders([appID])
        if !folders[index].itemIDs.contains(appID) {
            folders[index].itemIDs.append(appID)
        }
        tileOrder.removeAll { $0 == appID }
        reconcileAfterAppScan()
        onChange?(.content(animated: true))
    }

    /// 从文件夹移除应用，并恢复到顶层排序。
    ///
    /// - Parameters:
    ///   - appID: 应用标识。
    ///   - folderID: 当前所在文件夹标识。
    func removeApp(_ appID: String, from folderID: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else {
            return
        }

        folders[index].itemIDs.removeAll { $0 == appID }
        tileOrder.append(appID)
        reconcileAfterAppScan()
        onChange?(.content(animated: true))
    }

    /// 应用内存中的排序预览，不写入偏好文件。
    ///
    /// 调用方向：拖拽 Hover -> Pager -> Store -> 动画内容通知。
    ///
    /// - Parameters:
    ///   - draggedID: 被拖拽 Tile 标识。
    ///   - targetID: 目标 Tile 标识，拖拽项将移动到它之前。
    func previewMoveTile(_ draggedID: String, before targetID: String) {
        guard draggedID != targetID, searchText.trimmedNonEmpty == nil else {
            return
        }

        let updatedOrder = TileOrderMover.moving(draggedID, before: targetID, in: tileOrder)
        guard updatedOrder != tileOrder else { return }
        tileOrder = updatedOrder
        dragPreviewChanged = true
        onChange?(.content(animated: true))
    }

    func folder(withID id: String) -> LauncherFolder? {
        folders.first { $0.id == id }
    }

    func app(withID id: String) -> LauncherAppInfo? {
        apps.first { $0.id == id }
    }

    func isAppHidden(_ appID: String) -> Bool {
        hiddenAppIDs.contains(appID)
    }

    func apps(in folder: LauncherFolder) -> [LauncherAppInfo] {
        folder.itemIDs
            .compactMap(app(withID:))
            .filter(isAppVisibleInCurrentFilter)
    }

    // MARK: - 派生状态

    /// 根据当前排序模式生成最终顶层 Tile 顺序。
    private func orderedTiles() -> [LauncherTile] {
        let topLevelAppIDs = Set(topLevelApps().map(\.id))
        let folderTileIDs = Set(
            folders
                .filter(shouldShowFolder)
                .map(\.tileID)
        )
        let availableIDs = topLevelAppIDs.union(folderTileIDs)

        if sortMode == .name {
            return availableIDs
                .compactMap(tile(for:))
                .sorted { lhs, rhs in
                    lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
        }

        let orderedIDs = tileOrder.filter { availableIDs.contains($0) }
        let missingIDs = availableIDs
            .subtracting(orderedIDs)
            .sorted { lhs, rhs in
                tileTitle(for: lhs).localizedStandardCompare(tileTitle(for: rhs)) == .orderedAscending
            }

        return (orderedIDs + missingIDs).compactMap(tile(for:))
    }

    private func topLevelApps() -> [LauncherAppInfo] {
        let nestedIDs = Set(folders.flatMap(\.itemIDs))
        return apps.filter { app in
            !nestedIDs.contains(app.id) && isAppVisibleInCurrentFilter(app)
        }
    }

    private func tile(for id: String) -> LauncherTile? {
        if id.hasPrefix("folder:") {
            let folderID = String(id.dropFirst("folder:".count))
            guard let folder = folder(withID: folderID) else {
                return nil
            }
            return makeFolderTile(folder)
        }

        guard let app = app(withID: id) else {
            return nil
        }
        return makeAppTile(app)
    }

    private func makeAppTile(_ app: LauncherAppInfo) -> LauncherTile {
        LauncherTile(id: app.id, title: app.title, kind: .app(app))
    }

    private func makeFolderTile(_ folder: LauncherFolder) -> LauncherTile {
        LauncherTile(
            id: folder.tileID,
            title: folder.name,
            kind: .folder(folder, apps(in: folder))
        )
    }

    private func tileTitle(for id: String) -> String {
        tile(for: id)?.title ?? id
    }

    /// 移除失效标识、修复文件夹和顺序，并校正当前页码。
    ///
    /// 扫描或文件夹变更后调用。恢复启动数据时可关闭持久化，
    /// 避免启动阶段重复写入文件。
    ///
    /// - Parameter persist: 是否在协调完成后保存偏好。
    private func reconcileAfterAppScan(persist: Bool = true) {
        let validAppIDs = Set(apps.map(\.id))
        hiddenAppIDs = Set(hiddenAppIDs.filter { validAppIDs.contains($0) })

        folders = folders.compactMap { folder in
            var cleaned = folder
            cleaned.itemIDs = cleaned.itemIDs.filter { validAppIDs.contains($0) }
            return cleaned
        }

        let topLevelAppIDs = Set(topLevelApps().map(\.id))
        let folderTileIDs = Set(
            folders
                .filter(shouldShowFolder)
                .map(\.tileID)
        )
        let availableTileIDs = topLevelAppIDs.union(folderTileIDs)

        tileOrder = tileOrder.filter { availableTileIDs.contains($0) }
        let missingIDs = availableTileIDs
            .subtracting(tileOrder)
            .sorted { lhs, rhs in
                tileTitle(for: lhs).localizedStandardCompare(tileTitle(for: rhs)) == .orderedAscending
            }
        tileOrder.append(contentsOf: missingIDs)

        let visibleCount = max(visibleTiles.count, 1)
        if pageIndex * gridLayout.itemsPerPage >= visibleCount {
            pageIndex = 0
        }

        if persist {
            savePreferences()
        }
    }

    private func removeAppsFromFolders(_ appIDs: [String]) {
        guard !appIDs.isEmpty else {
            return
        }

        let appIDSet = Set(appIDs)
        for index in folders.indices {
            folders[index].itemIDs.removeAll { appIDSet.contains($0) }
        }
    }

    // MARK: - 持久化输出

    /// 捕获当前可持久化状态，并异步委托服务写入磁盘。
    ///
    /// 调用方向：Store 变更 -> `PreferencesStoring`；失败后回写 UI 状态。
    private func savePreferences() {
        let preferences = LauncherPreferences(
            sortMode: sortMode,
            tileOrder: tileOrder,
            folders: folders,
            gridLayout: gridLayout,
            hiddenAppIDs: hiddenAppIDs.sorted(),
            appFilterMode: appFilterMode
        )
        let store = preferencesStore
        Task {
            do {
                try await store.savePreferences(preferences)
            } catch {
                LumaEventLog.shared.write("preferences.save.failed", error.localizedDescription)
                await MainActor.run {
                    self.statusMessage = "Preferences could not be saved."
                    self.onChange?(.state)
                    NSSound.beep()
                }
            }
        }
    }

    private func uniqueFolderName(_ baseName: String, excluding folderID: String? = nil) -> String {
        let existingNames = Set(
            folders
                .filter { $0.id != folderID }
                .map { normalized($0.name) }
        )

        if !existingNames.contains(normalized(baseName)) {
            return baseName
        }

        var suffix = 2
        while existingNames.contains(normalized("\(baseName) \(suffix)")) {
            suffix += 1
        }
        return "\(baseName) \(suffix)"
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func isAppVisibleInCurrentFilter(_ app: LauncherAppInfo) -> Bool {
        let isHidden = hiddenAppIDs.contains(app.id)
        switch appFilterMode {
        case .visibleOnly:
            return !isHidden
        case .all:
            return true
        case .hiddenOnly:
            return isHidden
        }
    }

    private func shouldShowFolder(_ folder: LauncherFolder) -> Bool {
        if folder.itemIDs.isEmpty {
            return appFilterMode != .hiddenOnly
        }
        return !apps(in: folder).isEmpty
    }

    private func sortByTitle(_ lhs: LauncherAppInfo, _ rhs: LauncherAppInfo) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
