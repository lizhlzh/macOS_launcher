给 macOS_launcher / Luma 增加一套“交互诊断日志”，用于我每次编译安装后排查真实运行中的点击、按钮、滑动、分页、拖拽排序、拖拽建文件夹等问题。

目标：
不是做用户行为分析，而是本地开发调试日志。日志要能帮助定位：
1. 顶部按钮为什么点击不触发；
2. 点击 App 为什么会命中下一行；
3. 拖动排序为什么卡顿；
4. 拖动 App 到 App / Folder 时实际命中了哪个目标；
5. 滑动分页时 pageIndex、dragOffset、contentView.frame.origin 是否正确。

要求：
- 不引入第三方依赖。
- 使用现有 LumaEventLog 体系；如现有日志能力不够，可以扩展它。
- 日志必须在实际安装后的 .app 中可用。
- 菜单里的 Reveal Logs 仍然可以打开日志文件。
- 日志不要影响交互性能，尤其不能在 mouseDragged / draggingUpdated 高频路径里同步写磁盘。
- 高频事件必须节流或合并。
- 日志文件要限制大小，避免无限增长。
- 不要记录隐私信息，不要完整记录用户搜索词；最多记录 searchText 是否为空、长度、hash 或前后状态。

一、日志基础设施

检查现有：
Sources/MacOSLauncher/Services/Logging/LumaEventLog.swift

请扩展或新增方法，使其支持结构化交互日志。

建议新增：

enum LumaLogCategory: String {
    case lifecycle
    case header
    case hitTest
    case tile
    case drag
    case page
    case search
    case folder
    case performance
}

增加一个轻量方法：

func writeInteraction(
    _ category: LumaLogCategory,
    _ event: String,
    fields: [String: CustomStringConvertible?] = [:]
)

输出格式建议为单行 key=value，便于直接看：

2026-06-12T10:15:31.123Z category=hitTest event=pager.hit tileID=app:/Applications/xxx.app title=Safari pageIndex=0 point=423.0,215.0 contentOrigin=-1440.0,0.0 currentPage=0

或者 JSONL 也可以，但不要引入 Codable 复杂封装导致高频路径开销过大。

必须包含：
- ISO 时间戳；
- category；
- event；
- sessionID；
- thread/mainThread；
- 关键字段。

增加 sessionID：
- App 启动时生成一个 UUID，整个进程生命周期固定；
- 每次 Launcher show 时生成一个 presentationID；
- 每次拖拽开始时生成一个 dragID。

日志写入策略：
- 使用后台串行 DispatchQueue 写文件；
- UI 高频路径只入队，不同步写磁盘；
- 文件超过 5MB 时轮转：
  - 当前 luma.log -> luma.1.log
  - 最多保留 3 个文件
- 如果写日志失败，不影响 App 运行。

二、增加交互日志开关

为了实际安装后也能排查，默认开启 interaction logging。

但要提供一个统一开关，便于以后关闭：

建议在 LumaEventLog 中：

var isInteractionLoggingEnabled: Bool = true

或者读取 UserDefaults：

UserDefaults.standard.bool(forKey: "LumaInteractionLoggingDisabled")

逻辑：
- 默认开启；
- 如果 UserDefaults 中 LumaInteractionLoggingDisabled == true，则关闭交互日志。

可以在日志开头输出：

category=lifecycle event=logging.started enabled=true path=...

三、生命周期日志

文件：
Sources/MacOSLauncher/App/AppLifecycleCoordinator.swift
Sources/MacOSLauncher/Features/Launcher/Window/LauncherController.swift

在以下位置记录：

1. App 启动完成：
event=app.start

字段：
- sessionID
- appVersion 如果能取到
- build 如果能取到
- screenCount

2. Launcher show：
event=launcher.show

字段：
- presentationID
- targetScreen.frame
- panel.frame
- store.pageIndex
- store.visibleTiles.count
- grid rows/columns

3. Launcher hide：
event=launcher.hide

字段：
- presentationID
- reason，如果能区分 closeButton / escape / appLaunch / outsideClick

4. prepareForPresentation：
event=launcher.prepare

字段：
- pageIndex
- isEditing
- visibleTiles.count

四、顶部按钮日志

文件：
Sources/MacOSLauncher/Features/Launcher/UI/Header/HeaderButton.swift
Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift

给 HeaderButton 增加一个 debugName：

final class HeaderButton: NSControl {
    var debugName: String = "unknown"
}

配置按钮时设置：

sortButton.debugName = "sort"
layoutButton.debugName = "layout"
filterButton.debugName = "filter"
editButton.debugName = "edit"
folderButton.debugName = "folder"
rescanButton.debugName = "rescan"
closeButton.debugName = "close"

在 HeaderButton.mouseDown 记录：

event=header.mouseDown

字段：
- button
- isEnabled
- localPoint
- frame
- windowIsKey
- firstResponder

在实际 sendAction 前记录：

event=header.sendAction

字段：
- button
- action
- targetType

如果 action 未发送，记录：

event=header.actionSkipped

字段：
- button
- reason

在 LauncherRootView 的各个 selector 中记录：

showSortMenu -> event=header.action.showSortMenu
showLayoutMenu -> event=header.action.showLayoutMenu
showFilterMenu -> event=header.action.showFilterMenu
toggleEditing -> event=header.action.toggleEditing
createFolder -> event=header.action.createFolder
rescanApplications -> event=header.action.rescan
closeLauncher -> event=header.action.close

这样可以区分：
- 按钮没有命中；
- 按钮命中了但没有 sendAction；
- sendAction 了但 selector 没执行；
- selector 执行了但 UI 没变化。

五、RootView hitTest 日志

文件：
Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift

在 LauncherRootView.hitTest 中记录关键路径，但要节流，避免鼠标移动也打爆日志。只记录 mouseDown 触发的 hitTest 不容易区分，所以建议记录命中结果但只在命中 header / pager / overlay 时记录。

建议增加辅助方法：

private func logRootHitTest(
    point: NSPoint,
    result: String,
    detail: String? = nil
)

记录事件：

event=root.hitTest

字段：
- point
- result: folderOverlay/header.control/header.search/header.background/super/nil
- detail: buttonName 或 searchField
- headerFrame
- pagerFrame
- folderOverlayVisible

重点：
- 当点顶部按钮时，必须能看到 result=header.control detail=sort/layout/...
- 如果仍然 result=header.search 或 header.background，就说明按钮层级/坐标有问题。

六、Pager / Tile 点击命中日志

文件：
Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift

在 LauncherPagerView.hitTest / hitTestTile / tile open 链路中增加日志。

必须记录：

1. pager.hitTest.begin

字段：
- pointInPager
- bounds
- isInteractionSuspended
- pageIndex
- renderedPageCount
- contentView.frame.origin
- contentView.frame.size
- pageViews.keys

2. pager.hitTest.result

字段：
- pointInPager
- contentPoint 或 pagePoint
- hitTileID
- hitTitle
- hitFrame
- hitSuperviewFrame
- pageIndex
- currentPageFrame
- activeTileIDs.contains
- alphaValue

3. pager.hitTest.nil

字段：
- pointInPager
- reason
- pageIndex
- contentOrigin

如果生产代码继续用：

contentView.hitTest(contentPoint)?.enclosingLauncherTileView

也必须记录：
- contentPoint
- contentView.frame.origin
- returned view type
- enclosing tile id
- tile superview 是否为 currentPage

如果改成 currentPage-only hitTest，也必须记录：
- currentPage index
- pagePoint
- currentPage.bounds
- hit view type
- tileID

七、Tile 鼠标点击日志

文件：
Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift 中 LauncherTileView

在以下位置记录：

1. mouseDown

event=tile.mouseDown

字段：
- tileID
- title
- kind app/folder
- localPoint
- windowPoint
- frame
- superviewFrame
- isEditing
- pageIndex 如果能从 delegate 或 superview 推导
- timestamp

2. longPress triggered

event=tile.longPress

字段：
- tileID
- title
- elapsed

3. mouseUp

event=tile.mouseUp

字段：
- tileID
- title
- localPoint
- windowPoint
- isDraggingTile
- longPressTriggered
- isEditing
- pressedTileID
- currentTileID
- willOpen true/false
- skipReason

4. didRequestOpen 前

event=tile.open.request

字段：
- pressedTileID
- pressedTitle
- currentTileID
- currentTitle

在 LauncherPagerView delegate 方法中也记录：

func tileView(_ view: LauncherTileView, didRequestOpen tile: LauncherTile)

event=pager.open.forward

字段：
- tileID
- title
- kind
- pageIndex

在 LauncherRootView 的 pager open 方法中记录：

event=root.open

字段：
- tileID
- title
- kind
- action launch/openFolder

这样能完整看到：
mouseDown 的 tile 是谁；
mouseUp 的 tile 是谁；
最终打开的 tile 是谁。

八、滑动分页日志

文件：
Sources/MacOSLauncher/Features/Launcher/Window/LauncherController.swift
Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift
Sources/MacOSLauncher/Features/Launcher/State/LauncherStore.swift

在 LauncherPanel.scrollWheel 中记录，但必须节流。

记录：

1. scroll.begin

字段：
- deltaX
- deltaY
- precise
- phase
- momentumPhase
- pageWidth

2. scroll.changed 节流记录，每 80ms 最多一次

字段：
- rawDeltaX
- adjustedDeltaX
- accumulated
- direction
- pageDragOffset
- pageIndex

3. scroll.finish

字段：
- accumulated
- finalPageIndex
- previousPageIndex

在 LauncherStore：

beginPageDrag -> event=pageDrag.begin
updatePageDrag -> event=pageDrag.update，节流
finishPageDrag -> event=pageDrag.finish

字段：
- pageIndexBefore
- pageIndexAfter
- rawOffset
- pageDragOffset
- threshold
- pageWidth

在 LauncherPagerView.setPage 中记录：

event=pager.setPage

字段：
- index
- dragOffset
- animated
- previousIndex
- previousOffset
- realTargetX
- targetX
- contentView.frame.origin before/after
- shouldRecenterAfterAnimation

九、拖拽排序日志

文件：
Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift
Sources/MacOSLauncher/Features/Launcher/State/LauncherStore.swift

给每次拖拽生成 dragID。

在 LauncherTileView.mouseDragged 开始 native drag 前：

event=drag.source.begin

字段：
- dragID
- tileID
- title
- initialWindowPoint
- currentWindowPoint
- distance
- isEditing
- longPressTriggered
- timestampDelta

在 LauncherPagerView.tileViewDidBeginDragging：

event=drag.begin

字段：
- dragID
- tileID
- title
- sortModeBefore
- pageIndex
- tileOrderIndex
- visibleIndex

在 LauncherStore.beginDraggingTile：

event=store.drag.begin

字段：
- dragID
- tileID
- sortModeBefore
- sortModeAfter
- tileOrder.count
- visibleTiles.count

拖拽更新：

在 draggingUpdated / tileView(_:draggingUpdatedWith:) 中节流记录，每 80ms 最多一次：

event=drag.update

字段：
- dragID
- draggedID
- rawDraggingLocation
- convertedPagerPoint
- targetTileID
- targetTitle
- targetFrame
- pageIndex
- dropTargetIDBefore
- dropTargetIDAfter
- searchIsEmpty

在 updateDropTarget：

event=drag.target.change

字段：
- dragID
- draggedID
- oldTargetID
- newTargetID
- willPreviewMove true/false

在 LauncherStore.previewMoveTile：

event=store.drag.previewMove

字段：
- dragID
- draggedID
- targetID
- oldIndex
- newIndex
- changed true/false
- onChange dragPreview/content animated

注意：
- 不要每个 mouseDragged 都同步写；
- 高频 update 必须节流；
- target change 可以每次都记录，因为频率低很多。

拖拽结束：

在 performDragOperation：

event=drag.drop

字段：
- dragID
- draggedID
- targetID
- targetTitle
- targetKind app/folder
- operation createFolder/addToFolder/reorder/invalid
- pageIndex
- searchIsEmpty

在 tileViewDidEndDragging：

event=drag.end

字段：
- dragID
- tileID
- operation
- committed true/false
- reason

在 LauncherStore.endDraggingTile：

event=store.drag.end

字段：
- dragID
- commit
- dragPreviewChanged
- tileOrderChanged
- savedPreferences true/false

十、拖拽排序性能日志

需要增加轻量性能测量，帮助判断卡在哪。

在 LauncherPagerView：

1. performReload 开始/结束

event=perf.performReload

字段：
- animated
- refreshReplicas
- retargetRunningAnimations
- tileCount
- pageCount
- movingViews.count
- appearingViews.count
- durationMs

2. applyDragPreview / scheduleDragPreviewAnimation 如果已实现

event=perf.dragPreview

字段：
- movementCount
- durationMs
- coalesced true/false
- tileCount

3. refreshEdgeReplicas

event=perf.refreshEdgeReplicas

字段：
- renderedPageCount
- durationMs
- snapshotFirst true/false
- snapshotLast true/false

4. snapshot

event=perf.snapshot

字段：
- width
- height
- durationMs

要求：
- duration 使用 CACurrentMediaTime()。
- 高频性能日志也要节流。
- performReload 每次可以记录，因为频率不应太高。
- draggingUpdated 不要每次都记录完整性能日志。

十一、日志节流工具

新增一个简单的节流工具，避免散落 Date 判断。

建议文件：

Sources/MacOSLauncher/Services/Logging/InteractionLogThrottle.swift

实现：

final class InteractionLogThrottle {
    private var lastFire: [String: CFTimeInterval] = [:]

    func shouldLog(_ key: String, interval: CFTimeInterval) -> Bool {
        let now = CACurrentMediaTime()
        let last = lastFire[key] ?? 0
        guard now - last >= interval else {
            return false
        }
        lastFire[key] = now
        return true
    }
}

在 LauncherPagerView、LauncherPanel 或 LumaEventLog 中使用。

十二、日志字段格式要求

为了方便 grep，每条日志至少长这样：

time=...
session=...
presentation=...
category=...
event=...
key=value key=value ...

字段命名统一：

- sessionID
- presentationID
- dragID
- tileID
- title
- kind
- pageIndex
- renderedPageCount
- point
- windowPoint
- pagerPoint
- contentPoint
- pagePoint
- frame
- contentOrigin
- targetID
- targetTitle
- operation
- durationMs
- reason

坐标格式统一：

point=423.0,215.0
frame=48.0,120.0,160.0,140.0

不要直接打印 Optional(...)，封装格式化函数：

format(_ point: NSPoint) -> String
format(_ rect: NSRect) -> String
format(_ value: Any?) -> String

十三、日志查看体验

现有 Help -> Reveal Logs 继续可用。

同时在 App 启动时记录日志文件路径：

event=logging.path

字段：
- path
- maxSize
- rotationCount
- interactionEnabled

如果可行，在 Help 菜单增加一个菜单项：

Open Logs Folder

或者保持 Reveal Logs 即可，不强制。

十四、验收方式

编译安装后执行以下操作，然后打开日志文件检查：

1. 启动 App
应看到：
- app.start
- launcher.show
- launcher.prepare
- logging.path

2. 点击顶部 Sort
应看到：
- root.hitTest result=header.control detail=sort
- header.mouseDown button=sort
- header.sendAction button=sort
- header.action.showSortMenu

3. 点击第二行某个 App
应看到：
- root.hitTest 进入 pager
- pager.hitTest.begin
- pager.hitTest.result hitTileID=xxx
- tile.mouseDown tileID=xxx
- tile.mouseUp pressedTileID=xxx currentTileID=xxx willOpen=true
- tile.open.request tileID=xxx
- pager.open.forward tileID=xxx
- root.open tileID=xxx

如果实际打开下一行，日志必须能看出：
- mouseDown 命中的是哪一个；
- mouseUp 命中的是哪一个；
- didRequestOpen 传的是哪一个；
- contentPoint/pagePoint 是否整体偏移。

4. 滑动分页
应看到：
- scroll.begin
- pageDrag.begin
- scroll.changed / pageDrag.update 节流日志
- pageDrag.finish
- pager.setPage

5. 拖动排序
应看到：
- drag.source.begin
- drag.begin
- store.drag.begin
- drag.target.change
- store.drag.previewMove
- perf.dragPreview 或 perf.performReload
- drag.drop
- store.drag.end

6. 拖动 App 到 App 创建文件夹
应看到：
- drag.drop operation=createFolder
- store.drag.end commit=true
- folder.create 或 store.folder.create

十五、不要做的事情

- 不要把日志写在 tight loop 里同步落盘。
- 不要在 draggingUpdated 每次都写完整日志。
- 不要记录完整搜索关键词。
- 不要因为加日志改变交互逻辑。
- 不要把日志系统做成复杂的 analytics。
- 不要引入第三方 logging 框架。
- 不要让日志失败影响 App 功能。

十六、建议提交说明

提交信息：

Add interaction diagnostics logging

提交内容包括：
- LumaEventLog 扩展；
- InteractionLogThrottle；
- Header button 日志；
- Root/Pager/Tile hitTest 日志；
- Page scroll 日志；
- Drag/drop 日志；
- 轻量性能日志；
- 日志轮转。