继续在上一轮《0613.md》修改手册基础上优化 macOS_launcher / Luma。不要推翻上一版的主方向：点击命中、顶部按钮点击、中文本地化、App 名称解析这些已经基本稳定。本轮是在上一版基础上增加产品交互规则，并细化排序、编辑、筛选、文件夹和编辑态动画。

本轮新增/调整的问题：

1. 默认长按拖动排序后应直接提交，不需要再点对钩；
2. 只有用户主动点击顶部“编辑/排序”按钮进入整理模式后，才需要点击对钩提交；
3. 默认显示“可见应用”，不是“全部应用”；
4. 切换“可见应用 / 全部应用 / 已隐藏应用”显示模式时，如果当前不在第一页，应动画切换到第一页；
5. 创建文件夹后，应动画切换到新文件夹所在页面；
6. 点击编辑按钮后，App 右上角出现的拖动图标很难看，改成类似 iOS / Launchpad 的图标抖动，不要显示那个右上角丑图标。

重点文件：
- Sources/MacOSLauncher/Features/Launcher/State/LauncherStore.swift
- Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift
- Sources/MacOSLauncher/Features/Launcher/UI/Header/HeaderButton.swift
- Sources/MacOSLauncher/Features/Launcher/UI/Tile/LauncherTileView.swift，如果 Tile 仍在 LauncherViews.swift 中，就在当前文件中修改
- Sources/MacOSLauncher/Shared/Models/Models.swift
- Sources/MacOSLauncher/Shared/Localization/LumaLocalization.swift
- Tests/LumaTests/...

一、不要再改的内容

不要再改：
- LauncherRootView.hitTest
- LauncherRootView.mouseDown 坐标转换
- LauncherPagerView.hitTest 主路径
- HeaderButton.mouseDown 触发逻辑
- ApplicationDisplayNameResolver 的中文名称解析主逻辑
- 基础 L10n 结构
- 拖拽排序的轻量动画方向
- Layout 切换的高性能方向

本轮是新增交互语义，不是重写主架构。

二、明确两种排序模式

当前排序/编辑语义需要拆成两类：

1. 快速拖拽排序 Quick Reorder
- 默认状态下，用户长按 App 并拖动；
- 拖动过程中排序预览；
- 鼠标松开后立即提交；
- 自动保存 preferences；
- 不需要点击顶部对钩；
- 拖拽结束后退出临时拖拽状态。

2. 手动整理模式 Manual Edit / Jiggle Mode
- 用户主动点击顶部编辑/排序按钮进入；
- App 进入抖动状态；
- 用户可以连续拖动多个 App；
- 拖动过程中只更新内存顺序；
- 不立即保存；
- 用户点击顶部对钩后才提交保存；
- 如果用户取消、ESC、关闭 Launcher，可以按产品选择提交或回滚；本轮建议 ESC/关闭回滚，点击对钩提交。

注意：
当前代码里的 editButton 实际承担“进入整理模式 / 点击对钩提交”的功能。用户口中的“排序按钮”在这里可理解为当前 editButton/checkmark 按钮，不要和 Sort 菜单按钮混淆。

三、Store 增加编辑会话状态

在 LauncherStore 中增加：

enum ReorderSessionKind {
    case none
    case quickDrag
    case manualEdit
}

新增状态：

private(set) var reorderSessionKind: ReorderSessionKind = .none
private var manualEditOriginalTileOrder: [String]?

或者不用 enum，也可以用：

private(set) var isManualEditing = false
private var manualEditOriginalTileOrder: [String]?
private var isQuickDragging = false

推荐 enum，更清晰。

四、修改 beginEditing / endEditing 语义

当前 beginEditing / endEditing 只是开关 isEditing，不区分提交。需要改成：

func beginManualEditing() {
    guard reorderSessionKind != .manualEdit else { return }

    manualEditOriginalTileOrder = tileOrder
    reorderSessionKind = .manualEdit
    isEditing = true
    draggedTileID = nil

    LumaEventLog.shared.writeInteraction(
        .drag,
        "manualEdit.begin",
        fields: [
            "tileOrderCount": tileOrder.count
        ]
    )

    onChange?(.editing)
}

func commitManualEditing() {
    guard reorderSessionKind == .manualEdit else { return }

    savePreferences()

    reorderSessionKind = .none
    manualEditOriginalTileOrder = nil
    draggedTileID = nil
    isEditing = false

    LumaEventLog.shared.writeInteraction(
        .drag,
        "manualEdit.commit",
        fields: [
            "tileOrderCount": tileOrder.count
        ]
    )

    onChange?(.editing)
}

func cancelManualEditing() {
    guard reorderSessionKind == .manualEdit else { return }

    if let original = manualEditOriginalTileOrder {
        tileOrder = original
    }

    reorderSessionKind = .none
    manualEditOriginalTileOrder = nil
    draggedTileID = nil
    isEditing = false

    LumaEventLog.shared.writeInteraction(
        .drag,
        "manualEdit.cancel",
        fields: [
            "tileOrderCount": tileOrder.count
        ]
    )

    onChange?(.content(animated: false))
    onChange?(.editing)
}

修改 toggleEditing：

func toggleEditing() {
    if reorderSessionKind == .manualEdit {
        commitManualEditing()
    } else {
        beginManualEditing()
    }
}

顶部按钮显示：
- 非 manualEdit：显示整理/编辑图标；
- manualEdit：显示 checkmark，对应“完成排序”；
- 点击 checkmark 提交保存。

五、默认长按拖动排序直接提交

当前 beginDraggingTile 只有一个入口，容易把普通长按拖拽和手动编辑模式混在一起。需要新增参数：

func beginDraggingTile(_ tileID: String, kind: ReorderSessionKind)

或者：

func beginDraggingTile(_ tileID: String, commitPolicy: DragCommitPolicy)

推荐：

enum DragCommitPolicy {
    case autoCommit
    case manualCommit
}

新增状态：

private var activeDragCommitPolicy: DragCommitPolicy = .autoCommit

修改 beginDraggingTile：

func beginDraggingTile(_ tileID: String, commitPolicy: DragCommitPolicy) {
    if sortMode != .custom {
        tileOrder = orderedTiles().map(\.id)
        sortMode = .custom
    }

    tileOrderBeforeDrag = tileOrder
    dragPreviewChanged = false
    draggedTileID = tileID
    currentDragID = UUID().uuidString
    activeDragCommitPolicy = commitPolicy

    switch commitPolicy {
    case .autoCommit:
        reorderSessionKind = .quickDrag
        // 快速拖拽可以临时设置 isEditing = true 以复用拖拽 UI，
        // 但拖拽结束后必须自动退出。
        isEditing = true

    case .manualCommit:
        reorderSessionKind = .manualEdit
        isEditing = true
    }

    LumaEventLog.shared.writeInteraction(
        .drag,
        "drag.begin",
        fields: [
            "dragID": currentDragID ?? "nil",
            "tileID": tileID,
            "commitPolicy": commitPolicy == .autoCommit ? "autoCommit" : "manualCommit",
            "sessionKind": "\(reorderSessionKind)"
        ]
    )

    onChange?(.editing)
}

六、Tile/Pager 根据是否手动编辑决定 commit policy

在 LauncherTileView.mouseDragged 或 LauncherPagerView.tileViewDidBeginDragging 中判断当前是否是手动编辑模式。

建议在 Store 增加只读属性：

var isInManualEditMode: Bool {
    reorderSessionKind == .manualEdit
}

在 Pager：

func tileViewDidBeginDragging(_ view: LauncherTileView) {
    currentDragCommitted = false
    setPageRasterizationEnabled(false)

    let policy: DragCommitPolicy = store.isInManualEditMode ? .manualCommit : .autoCommit

    LumaEventLog.shared.writeInteraction(
        .drag,
        "tile.drag.begin",
        fields: [
            "tileID": view.tileID,
            "commitPolicy": policy == .autoCommit ? "autoCommit" : "manualCommit"
        ]
    )

    store.beginDraggingTile(view.tileID, commitPolicy: policy)
}

七、修改 endDraggingTile 规则

当前 endDraggingTile(commit:) 里 commit=false 会恢复旧 tileOrder。现在要区分 autoCommit 和 manualCommit。

建议：

func endDraggingTile(commit: Bool) {
    let dragID = currentDragID
    let policy = activeDragCommitPolicy
    let previewChanged = dragPreviewChanged

    switch policy {
    case .autoCommit:
        if commit, dragPreviewChanged {
            savePreferences()
        } else if !commit, let tileOrderBeforeDrag {
            tileOrder = tileOrderBeforeDrag
            onChange?(.content(animated: false))
        }

        // 快速拖拽结束后退出临时编辑状态
        reorderSessionKind = .none
        isEditing = false

    case .manualCommit:
        // 手动编辑模式下，拖拽结束只结束当前 drag，不保存，也不退出编辑。
        // 保存由 commitManualEditing 负责。
        // 取消整个 manual edit 才恢复 manualEditOriginalTileOrder。
        if !commit, let tileOrderBeforeDrag {
            // 单次拖拽取消，只回滚本次拖拽前状态，但仍留在 manual edit。
            tileOrder = tileOrderBeforeDrag
            onChange?(.content(animated: false))
        }

        reorderSessionKind = .manualEdit
        isEditing = true
    }

    tileOrderBeforeDrag = nil
    dragPreviewChanged = false
    draggedTileID = nil
    currentDragID = nil
    activeDragCommitPolicy = .autoCommit

    LumaEventLog.shared.writeInteraction(
        .drag,
        "drag.end",
        fields: [
            "dragID": dragID ?? "nil",
            "commit": commit,
            "previewChanged": previewChanged,
            "commitPolicy": policy == .autoCommit ? "autoCommit" : "manualCommit",
            "sessionKind": "\(reorderSessionKind)"
        ]
    )

    onChange?(.editing)
}

要求：
- 默认长按拖动：commit=true 后立即保存，拖拽结束后退出临时编辑；
- 手动编辑模式拖动：commit=true 后只保留内存排序，不保存；点击 checkmark 才保存；
- 手动编辑模式下，拖完一个 App 后仍然保持抖动编辑状态；
- 默认长按拖动结束后，不应继续留在编辑抖动状态。

八、修改拖拽结束判断

继续保留上一版建议：LauncherTileViewDelegate 需要传递 operation。

协议：

func tileViewDidEndDragging(_ view: LauncherTileView, operation: NSDragOperation)

在 LauncherTileView.draggingSession endedAt 中：

delegate?.tileViewDidEndDragging(self, operation: operation)

在 Pager：

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
            "operation": operation.rawValue,
            "committed": shouldCommit,
            "currentDragCommitted": currentDragCommitted,
            "hasPendingDragPreview": store.hasPendingDragPreview,
            "isManualEditMode": store.isInManualEditMode
        ]
    )

    currentDragCommitted = false
    setPageRasterizationEnabled(true)
    refreshEdgeReplicas()
}

九、默认显示可见应用，而不是全部应用

确认并强化默认值：

1. LauncherStore 默认值：
private(set) var appFilterMode: AppFilterMode = .visibleOnly

2. LauncherPreferences 默认值：
appFilterMode 应为 .visibleOnly。

3. 如果没有本地 preferences，默认 visibleOnly。

4. 如果读取旧 preferences 没有 appFilterMode 字段，默认 visibleOnly。

5. 不要因为隐藏 App、Rescan、Layout 切换、重新打开 Launcher 而自动切到 .all。

6. 如果用户明确选择 All Apps，可以保留该选择；但“初始默认”和“隐藏后默认视图”必须是 visibleOnly。

隐藏 App 后如果当前是 .all，仍建议自动切回 .visibleOnly，避免用户觉得隐藏失效。

十、切换可见/隐藏显示模式时动画到第一页

当前 setAppFilterMode 直接 pageIndex=0 并 content reload，视觉上可能不是“切换到第一页”，而是直接刷新。

新增 StoreChange：

case filterModeChanged(previousPageIndex: Int)

修改 setAppFilterMode：

func setAppFilterMode(_ mode: AppFilterMode) {
    guard appFilterMode != mode else { return }

    let previousPageIndex = pageIndex
    appFilterMode = mode
    pageIndex = 0
    pageDragRawOffset = 0
    pageDragOffset = 0

    savePreferences()

    LumaEventLog.shared.writeInteraction(
        .page,
        "filterMode.changed",
        fields: [
            "mode": mode.rawValue,
            "previousPageIndex": previousPageIndex,
            "targetPageIndex": 0
        ]
    )

    onChange?(.filterModeChanged(previousPageIndex: previousPageIndex))
}

RootView.handleStoreChange 增加：

case let .filterModeChanged(previousPageIndex):
    pager.reloadForFilterModeChange(from: previousPageIndex, to: 0)
    updatePageDots()
    updateHeader()
    updateStatus()

Pager 增加：

func reloadForFilterModeChange(from previousPageIndex: Int, to targetPageIndex: Int) {
    replicaRefreshWorkItem?.cancel()
    replicaRefreshWorkItem = nil

    performReload(animated: false, refreshReplicas: false, retargetRunningAnimations: false)

    let startPage = min(max(0, previousPageIndex), max(0, renderedPageCount - 1))
    let startOrigin = NSPoint(x: -CGFloat(startPage + 1) * bounds.width, y: 0)
    contentView.setFrameOrigin(startOrigin)

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

要求：
- 如果当前已经在第一页，直接刷新即可；
- 如果当前不在第一页，视觉上从当前页滑动到第一页；
- 切换 Visible / All / Hidden 都使用这条路径；
- 切换后 pageDots 更新为第一页。

十一、创建文件夹后动画切换到文件夹所在页

当前 createFolder 只是追加 folder 并刷新内容。需要在创建后定位到该 folder tile 所在页，并动画切过去。

新增 StoreChange：

case folderCreated(folderID: String, previousPageIndex: Int, targetPageIndex: Int)

修改 createFolder：

@discardableResult
func createFolder(named name: String? = nil, containing itemIDs: [String] = []) -> LauncherFolder {
    let previousPageIndex = pageIndex

    let validItemIDs = itemIDs.filter { app(withID: $0) != nil }
    let folder = LauncherFolder(
        id: UUID().uuidString,
        name: uniqueFolderName(name?.trimmedNonEmpty ?? L10n.text(.newFolder)),
        itemIDs: validItemIDs
    )

    removeAppsFromFolders(validItemIDs)
    folders.append(folder)
    tileOrder.removeAll { validItemIDs.contains($0) }
    tileOrder.append(folder.tileID)

    reconcileAfterAppScan()

    let targetIndex = visibleTiles.firstIndex(where: { $0.id == folder.tileID }) ?? max(0, visibleTiles.count - 1)
    let targetPageIndex = targetIndex / max(1, gridLayout.itemsPerPage)

    pageIndex = targetPageIndex
    savePreferences()

    LumaEventLog.shared.writeInteraction(
        .folder,
        "folder.created",
        fields: [
            "folderID": folder.id,
            "folderTileID": folder.tileID,
            "previousPageIndex": previousPageIndex,
            "targetPageIndex": targetPageIndex,
            "itemCount": validItemIDs.count
        ]
    )

    onChange?(
        .folderCreated(
            folderID: folder.id,
            previousPageIndex: previousPageIndex,
            targetPageIndex: targetPageIndex
        )
    )

    return folder
}

RootView.handleStoreChange：

case let .folderCreated(_, previousPageIndex, targetPageIndex):
    pager.reloadForFolderCreation(from: previousPageIndex, to: targetPageIndex)
    updatePageDots()
    updateHeader()
    updateStatus()

Pager 增加：

func reloadForFolderCreation(from previousPageIndex: Int, to targetPageIndex: Int) {
    replicaRefreshWorkItem?.cancel()
    replicaRefreshWorkItem = nil

    performReload(animated: false, refreshReplicas: false, retargetRunningAnimations: false)

    let startPage = min(max(0, previousPageIndex), max(0, renderedPageCount - 1))
    let targetPage = min(max(0, targetPageIndex), max(0, renderedPageCount - 1))

    contentView.setFrameOrigin(NSPoint(x: -CGFloat(startPage + 1) * bounds.width, y: 0))

    if startPage != targetPage {
        setPage(
            index: targetPage,
            dragOffset: 0,
            animated: true,
            previousIndex: startPage,
            previousOffset: 0
        )
    } else {
        setPage(index: targetPage, dragOffset: 0, animated: false)
    }

    scheduleEdgeReplicaRefresh(after: 0.35)
}

要求：
- 点击顶部新建文件夹后，自动切到新文件夹所在页；
- App-to-App 创建文件夹后，也自动切到新文件夹所在页；
- 如果新文件夹就在当前页，不做多余滑动；
- pageDots 同步更新；
- 不要打开文件夹 overlay，除非现有产品已有这个行为，本轮只要求切页。

十二、编辑态改成 iOS 风格抖动，不要显示右上角拖动图标

当前 LauncherTileView 有 editBadge，右上角显示 line.3.horizontal 图标。这个视觉很差，改为 iOS / Launchpad 风格抖动。

要求：
1. 进入 manual edit mode 后，所有可见 App / Folder 图标轻微抖动；
2. 不显示右上角 editBadge；
3. 拖动时，被拖动的 Tile 暂停抖动或降低透明度；
4. 退出编辑后停止所有动画；
5. 尊重 Reduce Motion，如果系统开启减少动态效果，则不抖动，只显示轻微高亮或缩放；
6. 抖动只在 manual edit mode 下持续显示；
7. 默认快速长按拖动时，可以短暂进入拖拽状态，但拖拽结束后不要长期抖动。

十三、删除或隐藏 editBadge

在 LauncherTileView 中：

- 保留 editBadge 属性也可以，但默认永远隐藏；
- 更推荐移除 editBadge 的图标设置和 layout；
- 不要再显示右上角 line.3.horizontal；
- 如果后续需要删除按钮，可以单独设计 iOS 风格左上角 minus，不在本轮做。

修改：

editBadge.isHidden = true

或者彻底删除：
- private let editBadge = NSImageView()
- addSubview(editBadge)
- editBadge layout
- editBadge image 配置

短期稳妥：保留属性但隐藏，不影响编译范围。

十四、实现 wiggle 动画

在 LauncherTileView 中新增：

private func updateWiggleAnimation() {
    if shouldReduceMotion {
        layer?.removeAnimation(forKey: "luma.wiggle.rotation")
        layer?.removeAnimation(forKey: "luma.wiggle.position")
        return
    }

    if isEditing && !isDraggingTile {
        startWiggleIfNeeded()
    } else {
        stopWiggle()
    }
}

private var shouldReduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

private func startWiggleIfNeeded() {
    wantsLayer = true
    guard layer?.animation(forKey: "luma.wiggle.rotation") == nil else {
        return
    }

    let seed = abs(tileID.hashValue)
    let phase = CFTimeInterval(seed % 100) / 100.0 * 0.12
    let angle = CGFloat(0.018 + Double(seed % 6) / 1000.0)

    let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
    rotation.values = [-angle, angle, -angle * 0.7]
    rotation.duration = 0.18
    rotation.beginTime = CACurrentMediaTime() + phase
    rotation.repeatCount = .infinity
    rotation.isRemovedOnCompletion = false
    rotation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

    let translation = CAKeyframeAnimation(keyPath: "transform.translation.y")
    translation.values = [0, -1.0, 0.6, 0]
    translation.duration = 0.24
    translation.beginTime = CACurrentMediaTime() + phase / 2
    translation.repeatCount = .infinity
    translation.isRemovedOnCompletion = false
    translation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

    layer?.add(rotation, forKey: "luma.wiggle.rotation")
    layer?.add(translation, forKey: "luma.wiggle.position")
}

private func stopWiggle() {
    layer?.removeAnimation(forKey: "luma.wiggle.rotation")
    layer?.removeAnimation(forKey: "luma.wiggle.position")
    layer?.transform = CATransform3DIdentity
}

在以下位置调用：
- update(tile:metrics:isEditing:) 后；
- setEditing(_:dragged:) 后；
- mouseDragged 开始拖拽后；
- draggingSession endedAt 后；
- updateAppearance(animated:) 之后不要覆盖 wiggle 动画。

十五、区分 manual edit 抖动和 quick drag

现在 TileView 只知道 isEditing，可能无法区分是 manual edit 还是 quick drag。需要传入更清晰状态。

方案 A：
让 LauncherStore 增加：

var shouldShowJiggle: Bool {
    reorderSessionKind == .manualEdit
}

Pager.updateEditingState：

view.setEditing(
    store.shouldShowJiggle,
    dragged: store.draggedTileID == view.tileID
)

TileView.setEditing 的 editing 参数改成 “showJiggle”。

方案 B：
保留 isEditing 但增加 isManualEditing 参数。

推荐方案 A，更少改动。

要求：
- toolbar 手动编辑：showJiggle=true；
- quick drag：showJiggle=false，或者只在拖拽中的 tile 改外观；
- quick drag 结束后所有图标不抖动；
- manual edit 下拖完一个 App 后仍然继续抖动，直到点 checkmark。

十六、Header 编辑按钮文案和图标

当前 editButton 使用 slider.horizontal.3，manual edit 下变成 checkmark。可以保留，但建议更清晰：

非编辑态：
- symbol: "square.grid.3x3"
- tooltip: L10n.text(.editTooltip) 或新增 L10n.text(.organizeApps)
- 无文字，仅图标

手动编辑态：
- symbol: "checkmark"
- tooltip: L10n.text(.doneEditingTooltip) 或 “完成排序”

L10n 可新增：
- organizeApps: 中文“整理应用”，英文“Organize Apps”
- doneSorting: 中文“完成排序”，英文“Done Sorting”

十七、筛选模式动画切第一页验收

实际验收：
1. 切到第 2 页或第 3 页；
2. 点击 Filter -> 已隐藏应用；
3. 应看到页面动画回到第一页；
4. pageDots 当前页变成 0；
5. 切回 可见应用 / 全部应用 也同样从当前页动画回第一页；
6. 如果本来就在第一页，不做多余动画。

日志应出现：

filterMode.changed previousPageIndex=2 targetPageIndex=0
pager.reloadForFilterModeChange from=2 to=0
pager.setPage animated=true pageIndex=0

十八、创建文件夹切页验收

实际验收：
1. 当前在第一页；
2. 顶部点击新建文件夹；
3. 如果新文件夹被添加到最后一页，应动画切到最后一页；
4. pageDots 对应最后一页；
5. App-to-App 创建文件夹也应切到新文件夹所在页；
6. 不应卡顿，不应错误打开 folder overlay。

日志应出现：

folder.created previousPageIndex=0 targetPageIndex=N
pager.reloadForFolderCreation from=0 to=N
pager.setPage animated=true pageIndex=N

十九、排序提交验收

默认快速拖拽：
1. 不点击顶部编辑按钮；
2. 长按 App 并拖动排序；
3. 松开鼠标；
4. 顺序立即保持；
5. 关闭再打开仍保持；
6. 不需要点击对钩。

日志应出现：

drag.begin commitPolicy=autoCommit
drag.previewMove
tile.draggingSessionEnded operation=move
drag.end commit=true commitPolicy=autoCommit
manualEdit 不应出现

手动整理模式：
1. 点击顶部编辑/排序按钮；
2. 图标开始抖动；
3. 拖动多个 App；
4. 松手后顺序暂时保持；
5. 不退出抖动；
6. 点击对钩；
7. 保存排序并退出抖动；
8. 关闭再打开仍保持。

日志应出现：

manualEdit.begin
drag.begin commitPolicy=manualCommit
drag.previewMove
drag.end commit=true commitPolicy=manualCommit
manualEdit.commit

取消场景：
1. 进入手动整理模式；
2. 拖动排序；
3. 按 ESC 或关闭 Launcher；
4. 如果产品定义为取消，则恢复进入编辑前顺序；
5. 日志 manualEdit.cancel。

二十、Layout 卡顿优化继续保留

上一版关于 layoutChanged / reloadForLayoutChange / 延迟 refreshEdgeReplicas 的要求继续保留。不要因为新增 filter/folder 动画又回到 .content(animated: true)。

新增 StoreChange 后建议最终包含：

enum LauncherStoreChange {
    case content(animated: Bool)
    case state
    case search
    case pageDrag
    case pageSettled(previousIndex: Int, previousOffset: CGFloat)
    case editing
    case presentation
    case dragPreview
    case layoutChanged
    case filterModeChanged(previousPageIndex: Int)
    case folderCreated(folderID: String, previousPageIndex: Int, targetPageIndex: Int)
}

二十一、测试要求

新增/修改测试：

1. Quick drag auto commit
- 默认非 manual edit；
- beginDraggingTile(appA, commitPolicy: .autoCommit)
- previewMoveTile(appA, before: appC)
- endDraggingTile(commit: true)
- tileOrder 保持新顺序；
- preferences 保存；
- isEditing=false；
- reorderSessionKind=.none。

2. Manual edit requires checkmark
- beginManualEditing()
- beginDraggingTile(appA, commitPolicy: .manualCommit)
- previewMoveTile(appA, before: appC)
- endDraggingTile(commit: true)
- tileOrder 内存保持新顺序；
- preferences 未保存；
- isEditing=true；
- commitManualEditing()
- preferences 保存；
- isEditing=false。

3. Manual edit cancel
- beginManualEditing()
- previewMoveTile
- cancelManualEditing()
- tileOrder 恢复原始顺序。

4. Filter mode page reset animation
- pageIndex=2；
- setAppFilterMode(.hiddenOnly)
- StoreChange 为 .filterModeChanged(previousPageIndex: 2)
- pageIndex=0。

5. Folder created target page
- 使用足够多 App 让 folder 出现在第 2/3 页；
- createFolder()
- StoreChange 为 .folderCreated；
- pageIndex == folder 所在页。

6. Jiggle mode
- manual edit 下 TileView 应有 wiggle animation key；
- quick drag 结束后不应有 wiggle；
- Reduce Motion 下不添加 wiggle 动画。

7. Header button
- manual edit 下 editButton 图标为 checkmark；
- 退出后恢复普通整理图标；
- tooltip 中文为“整理应用 / 完成排序”。

二十二、不要做的事

- 不要把默认 quick drag 做成必须点 checkmark；
- 不要让普通长按拖拽结束后还留在抖动编辑态；
- 不要让 manual edit 的拖动每次都立即保存；
- 不要在 filter 切换时直接无动画刷新到第一页；
- 不要创建文件夹后仍停留在原页面；
- 不要继续显示右上角 line.3.horizontal editBadge；
- 不要用大量 view 重建实现抖动；
- 不要在所有 App 上同时做重型动画，wiggle 应该是轻量 CAAnimation；
- 不要回退到 .content(animated: true) 处理布局切换；
- 不要再改已稳定的 hitTest 坐标逻辑。