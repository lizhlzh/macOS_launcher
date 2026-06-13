
````markdown
请严格执行本轮收口任务。不要写方案，不要全仓库扫描，不要修改 Tests，不要运行 swift test。

本轮只修 4 个问题：
1. 用轻量副本页替代 edge replicas 的整页快照；
2. 修复拖拽松手后卡顿、图标灰色停留约 1 秒；
3. 修复点击 Pager 空白区域 / 背景空白区域不能退出 Launcher；
4. 对高频 hitTest 日志做最小降噪。

只允许修改：
- Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift

禁止修改：
- Tests
- Package.swift
- HeaderButton.swift
- LauncherStore.swift，除非编译必须
- LauncherRootView.mouseDown 坐标转换算法
- HeaderButton 布局
- AppIcon 打包脚本
- 拖拽排序状态机
- Layout transition 动画
- App 名称解析
- 背景、壁纸、启动动画
- 不要新增第三方依赖
- 不要 commit，不要 push

最后只运行：
swift build

---

## 一、用轻量副本页替代整页快照

### 当前问题

现在 `refreshEdgeReplicas()` 用整页快照实现首尾循环分页：

```swift
leadingReplica.image = snapshot(of: lastPage)
trailingReplica.image = snapshot(of: firstPage)
````

`snapshot(of:)` 内部使用：

```swift
bitmapImageRepForCachingDisplay
cacheDisplay
```

这会造成整页 CPU 渲染。日志里一次 `pager.refreshEdgeReplicas` 可达 250ms~300ms+。拖拽松手时如果同步刷新，会造成卡顿和图标灰色停留。

### 目标

* 不再为首尾循环分页生成整页 `NSImage` 快照；
* 改为真实但不可交互的轻量副本页；
* 副本页只渲染图标和标题；
* 副本页不参与 hitTest、不响应点击、不支持拖拽、不注册 trackingArea；
* 保持当前循环分页视觉效果；
* 保持当前 `setPage(...)` 的 recenter 机制；
* 不影响真实 `pageViews` / `LauncherTileView`；
* 不影响拖拽排序、打开应用、右键菜单。

### 重要说明

轻量副本页不是最终停留页。它只用于首尾循环滑动过程中的视觉占位。

当前 `setPage(...)` 已经有类似逻辑：

* 从第一页循环到最后一页时，动画目标先到 leading replica；
* 动画完成后，无动画 recenter 到真实 lastPage；
* 从最后一页循环到第一页时，动画目标先到 trailing replica；
* 动画完成后，无动画 recenter 到真实 page0。

本轮必须保留这个 `recenterAfterAnimation / recenterOrigin` 机制，不要改坏。

---

### A. 替换 leadingReplica / trailingReplica 类型

找到 `LauncherPagerView` 里原来的：

```swift
private let leadingReplica = NSImageView()
private let trailingReplica = NSImageView()
```

或等价定义。

替换为：

```swift
private let leadingReplica = LauncherReplicaPageView()
private let trailingReplica = LauncherReplicaPageView()
```

要求：

* 变量名保持 `leadingReplica` / `trailingReplica`，减少调用点改动；
* 类型必须是新的轻量副本页，不再是 `NSImageView`；
* 添加到 `contentView` 的位置保持原有逻辑；
* 副本页必须 `hitTest` 返回 `nil`。

---

### B. 新增轻量副本页视图

在 `LauncherViews.swift` 中新增两个 private class，放在 `LauncherPagerView` 附近即可。

#### 1. LauncherReplicaPageView

职责：

* 只负责显示一页的副本 tile；
* 不处理事件；
* 不持有业务状态；
* 每次 render 根据传入 items 重建或复用子视图；
* 子视图数量最多一页 `itemsPerPage`，允许简单 remove/recreate。

推荐实现：

```swift
@MainActor
private final class LauncherReplicaPageView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func render(
        items: [(tile: LauncherTile, frame: NSRect)],
        store: LauncherStore,
        metrics: LauncherGridMetrics
    ) {
        subviews.forEach { $0.removeFromSuperview() }

        for item in items {
            let tileView = LauncherReplicaTileView(
                tile: item.tile,
                store: store,
                metrics: metrics
            )
            tileView.frame = item.frame
            addSubview(tileView)
        }
    }

    func clear() {
        subviews.forEach { $0.removeFromSuperview() }
    }
}
```

#### 2. LauncherReplicaTileView

职责：

* 只显示 icon + title；
* 不注册拖拽；
* 不注册 tracking；
* 不响应 hitTest；
* 样式尽量与 `LauncherTileView` 视觉一致；
* 不要复用 `LauncherTileView`，避免带入交互、拖拽、hover、menu、jiggle 等行为。

推荐实现：

```swift
@MainActor
private final class LauncherReplicaTileView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metrics: LauncherGridMetrics

    override var isFlipped: Bool { true }

    init(
        tile: LauncherTile,
        store: LauncherStore,
        metrics: LauncherGridMetrics
    ) {
        self.metrics = metrics
        super.init(frame: .zero)

        wantsLayer = true
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

        titleLabel.stringValue = tile.title
        iconView.image = image(for: tile, store: store, metrics: metrics)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
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

        iconView.frame = NSRect(
            x: iconX,
            y: iconY,
            width: metrics.iconSize,
            height: metrics.iconSize
        )

        titleLabel.frame = NSRect(
            x: 2,
            y: iconView.frame.maxY + metrics.iconTitleSpacing,
            width: bounds.width - 4,
            height: metrics.titleHeight
        )
    }

    private func image(
        for tile: LauncherTile,
        store: LauncherStore,
        metrics: LauncherGridMetrics
    ) -> NSImage? {
        switch tile.kind {
        case let .app(app):
            return store.appIcon(for: app, size: metrics.iconSize)
        case let .folder(_, apps):
            return FolderIconRenderer.image(
                apps: apps,
                store: store,
                size: metrics.iconSize
            )
        }
    }
}
```

如果已有类型名称冲突，可以改成 `EdgeReplicaPageView` / `EdgeReplicaTileView`，但职责不变。

---

### C. 修改 refreshEdgeReplicas()

保留方法名 `refreshEdgeReplicas()`，避免大范围改调用点，但内部不要再做 snapshot。

改成类似：

```swift
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

    leadingReplica.frame = NSRect(
        x: 0,
        y: 0,
        width: bounds.width,
        height: bounds.height
    )

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
```

---

### D. 新增 replicaItems(for:)

在 `LauncherPagerView` 中新增：

```swift
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
```

说明：

* `frameForTile(at:)` 现在内部已经按 `index % metrics.itemsPerPage` 计算本页内位置；
* 所以这里可以直接传全局 index；
* 不要给 replica tile 加 page offset；
* replica page 自己的 frame 已经在 leading/trailing 位置。

---

### E. 删除整页 snapshot 函数

删除：

```swift
private func snapshot(of view: NSView) -> NSImage?
```

以及仅用于 edge replicas 的整页 bitmap 逻辑。

注意：

* 不要删除 `LauncherTileView.dragPreviewImage()`；
* 拖拽图标预览仍可以保留小图快照；
* 允许 `LauncherTileView.dragPreviewImage()` 中继续使用 `bitmapImageRepForCachingDisplay`；
* 禁止 edge replica 使用 `bitmapImageRepForCachingDisplay / cacheDisplay`。

---

### F. 排序后副本页刷新规则

轻量副本页是 `store.visibleTiles + metrics` 派生出来的缓存视图。

规则：

1. 拖拽排序过程中不要刷新 `leadingReplica / trailingReplica`；
2. 拖拽提交后，如果 `shouldCommit == true`，调用 `scheduleEdgeReplicaRefresh(after: 0.25)`；
3. `scheduleEdgeReplicaRefresh` 最终调用 `refreshEdgeReplicas()`；
4. 此时 `refreshEdgeReplicas()` 只重新 render 轻量副本页，不做整页 bitmap snapshot；
5. 不要在 `performDropWith / performDragOperation` 的 defer 中刷新副本页；
6. 不要同步刷新副本页；
7. 本轮先采用“排序提交后延迟刷新一次”的简单策略；
8. 不要做“只在第一页或最后一页受影响时刷新”的复杂优化。

---

### G. 初始化和布局要求

确认 `leadingReplica / trailingReplica` 仍然被添加到 `contentView`。

如果原先是：

```swift
contentView.addSubview(leadingReplica)
contentView.addSubview(trailingReplica)
```

可以保留。

注意：

* `leadingReplica` 位于 `x = 0`；
* 正式 page0 位于 `x = bounds.width`；
* 正式 pageN 位于 `x = CGFloat(pageIndex + 1) * bounds.width`；
* `trailingReplica` 位于 `x = CGFloat(renderedPageCount + 1) * bounds.width`；
* 不要改变当前 `contentView` 的 origin 计算；
* 不要改坏 `setPage(...)` 的首尾 recenter 逻辑。

---

### H. 绝对不要做

* 不要用 `LauncherTileView` 作为 replica 子视图；
* 不要注册拖拽；
* 不要添加 trackingArea；
* 不要支持右键菜单；
* 不要让副本页 hitTest；
* 不要使用 `NSImageView` 整页快照；
* 不要调用 `bitmapImageRepForCachingDisplay` 生成整页图；
* 不要改变循环分页的 content origin 计算；
* 不要改 `setPage(...)` 的 recenter 机制。

---

## 二、修拖拽松手灰色卡顿

### 当前问题

拖拽 drop 路径和 drag end 路径会同步 `refreshEdgeReplicas()`。即使本轮改成轻量副本页，也不应该在松手路径同步做刷新。

另外，`LauncherTileView.draggingSession(_:endedAt:operation:)` 当前是在 delegate 处理之后才恢复外观，导致 delegate 中有重活时，图标保持灰色 alpha。

### A. 先恢复视觉，再调用 delegate

把 `LauncherTileView.draggingSession(_:endedAt:operation:)` 改成：

```swift
func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    isDraggingTile = false
    mouseDownEvent = nil

    // 先恢复视觉，避免 delegate 中的刷新阻塞导致图标灰色停留。
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
```

要求：

* `updateAppearance(animated: false)` 必须在 `delegate?.tileViewDidEndDragging(...)` 之前；
* 不要用 `animated: true`；
* 不要改变排序提交逻辑。

---

### B. performDragOperation defer 只保留状态

把 `LauncherPagerView.performDragOperation` 的 defer 改成：

```swift
defer {
    currentDragCommitted = didCommitDrop
    dropTargetID = nil
}
```

不要在这里调用：

```swift
setPageRasterizationEnabled(true)
refreshEdgeReplicas()
scheduleEdgeReplicaRefresh(...)
```

---

### C. tileView(_:performDropWith:) defer 只保留状态

把 `LauncherPagerView.tileView(_:performDropWith:)` 的 defer 改成：

```swift
defer {
    currentDragCommitted = didCommitDrop
    dropTargetID = nil
}
```

不要在这里调用：

```swift
setPageRasterizationEnabled(true)
refreshEdgeReplicas()
scheduleEdgeReplicaRefresh(...)
```

---

### D. tileViewDidEndDragging 末尾延迟刷新

保留现有提交判断：

```swift
let shouldCommit =
    currentDragCommitted || hasPendingDragPreview
```

调用：

```swift
store.endDraggingTile(commit: shouldCommit)
```

之后末尾改成：

```swift
currentDragCommitted = false
setPageRasterizationEnabled(true)

if shouldCommit {
    scheduleEdgeReplicaRefresh(after: 0.25)
}
```

不要同步调用：

```swift
refreshEdgeReplicas()
```

说明：

* 排序取消时可以不刷新副本页；
* 排序提交后延迟刷新一次轻量副本页；
* `scheduleEdgeReplicaRefresh` 内部必须保留 cancel 合并逻辑。

---

### E. tile.drag.end 日志补充字段

在 `tile.drag.end` 日志 fields 中加入：

```swift
"replicaRefresh": shouldCommit ? "scheduled" : "skipped"
```

---

## 三、修点击空白处不退出

### 当前问题

`LauncherRootView.hitTest` 在 Pager 空白处返回 nil，导致 `LauncherRootView.mouseDown` 收不到事件。即使收到，`mouseDown` 里也会因为 `pager.frame.contains(layoutPoint)` 直接 return。

### 目标

* 点击 Tile：打开或拖动 Tile；
* 点击 Header 控件：正常响应；
* 点击搜索框：聚焦搜索；
* 点击 Pager 空白：关闭 Launcher；
* 点击根背景空白：关闭 Launcher；
* FolderOverlay 仍交给 overlay 处理。

---

### A. 修改 LauncherRootView.hitTest 的 Pager 分支

当前大致是：

```swift
if pager.frame.contains(layoutPoint) {
    let pagerPoint = ...
    let result = pager.hitTest(pagerPoint)
    ...
    return result
}
```

改成：

```swift
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
```

---

### B. 修改 LauncherRootView.hitTest 最后的 outside 分支

当前：

```swift
logRootHitTest(rawPoint: point, layoutPoint: layoutPoint, result: "outside")
return nil
```

改成：

```swift
logRootHitTest(rawPoint: point, layoutPoint: layoutPoint, result: "outside.closeTarget")
return self
```

---

### C. 修改 LauncherRootView.mouseDown

当前 Pager 分支大致是：

```swift
if pager.frame.contains(layoutPoint) {
    return
}
```

改成：

```swift
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
```

---

### D. Header 区域暂时保持不关闭

Header 背景点击可以先不关闭，避免误触。不要改 Header 控件逻辑。

---

### E. FolderOverlay 逻辑不要动

如果 `folderOverlay` 存在并命中 overlay，仍然交给 overlay。不要破坏文件夹浮层。

---

## 四、最小日志降噪

当前 hitTest 日志过密。只做最小降噪，不要重构日志系统。

### A. hitTestTile 命中日志必须 throttle

找到 `hitTestTile` 中类似：

```swift
LumaEventLog.shared.writeInteraction(
    .hitTest,
    "pager.tileHit.hit",
    ...
)
```

改成带 throttle：

```swift
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
```

注意：

* 不要删除 hitTest 日志；
* 只降低高频重复命中；
* 不要影响 drag target 日志。

### B. 必须保留这些关键拖拽日志

不要删除：

```text
tile.mouseDragged.beginSession
tile.drag.begin
drag.begin
drag.targetChanged
drag.previewMove
tile.drag.end
drag.end
pager.refreshEdgeReplicaPages
```

---

## 五、保持不变的逻辑

本轮禁止修改这些逻辑：

```swift
shouldCommit = currentDragCommitted || hasPendingDragPreview
```

禁止修改：

* `beginDraggingTile`
* `endDraggingTile`
* `previewMoveTile`
* Option + app-to-app 才创建文件夹
* app -> folder 添加到已有文件夹
* Layout transition 的 `CATransition + scale`
* HeaderButton 左对齐布局
* AppIcon 打包脚本
* `setPage(...)` 的 recenter 机制

---

## 六、自检命令

修改后执行：

```bash
grep -n "snapshot(of" Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift
```

应无结果。

执行：

```bash
grep -n "bitmapImageRepForCachingDisplay\\|cacheDisplay(in:" Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift
```

允许只出现在 `LauncherTileView.dragPreviewImage` 附近；
不允许出现在 edge replica / `refreshEdgeReplicas` 相关代码中。

执行：

```bash
grep -n "leadingReplica.image\\|trailingReplica.image" Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift
```

应无结果。

执行：

```bash
grep -n "LauncherReplicaPageView\\|LauncherReplicaTileView\\|refreshEdgeReplicaPages" Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift
```

应能看到新增轻量副本页和日志。

执行：

```bash
grep -n "performDragOperation" -A 30 Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift
```

确认 `performDragOperation` 的 defer 中没有：

```swift
refreshEdgeReplicas()
setPageRasterizationEnabled(true)
scheduleEdgeReplicaRefresh
```

执行：

```bash
grep -n "performDropWith" -A 35 Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift
```

确认 `performDropWith` 的 defer 中没有：

```swift
refreshEdgeReplicas()
setPageRasterizationEnabled(true)
scheduleEdgeReplicaRefresh
```

执行：

```bash
grep -n "tileViewDidEndDragging" -A 45 Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift
```

确认里面是：

```swift
setPageRasterizationEnabled(true)
if shouldCommit {
    scheduleEdgeReplicaRefresh(after: 0.25)
}
```

而不是：

```swift
refreshEdgeReplicas()
```

执行：

```bash
grep -n "pager.blank\\|outside.closeTarget\\|pagerBlankClick" Sources/MacOSLauncher/Features/Launcher/UI/LauncherViews.swift
```

应能看到空白点击关闭逻辑。

最后运行：

```bash
swift build
```

不要运行：

```bash
swift test
```

---

## 七、手动验收

构建安装后手动验证：

1. 打开 Launcher 后左右分页仍然能循环；
2. 从第一页往左滑，能看到最后一页副本；
3. 从最后一页往右滑，能看到第一页副本；
4. 滑到副本页后，动画结束应无感 recenter 到真实正式页；
5. 副本页不能点击、不能拖拽、不能右键；
6. 拖动排序松手后，图标不再灰色停留；
7. 拖动排序仍然保存；
8. 排序后再循环分页，首尾副本页显示的是新顺序；
9. 点击 Pager 空白区域会关闭 Launcher；
10. 点击背景空白区域会关闭 Launcher；
11. 点击 Tile 不受影响；
12. 点击 Header 按钮和搜索框不受影响；
13. 行列切换 transition 不受影响；
14. Header 按钮左对齐不受影响。

---

## 八、完成后报告

只报告：

1. 修改了哪些文件；
2. 是否已用轻量副本页替代整页快照；
3. 是否已删除 edge replica 的 bitmap snapshot；
4. 是否已保持首尾循环分页 recenter 机制；
5. 是否已把拖拽结束同步刷新改为延迟 schedule；
6. 是否已让图标恢复提前到 delegate 之前；
7. 是否已修复 pager blank / outside blank 点击关闭；
8. swift build 是否通过；
9. 明确说明没有修改 Tests、没有运行 swift test。

