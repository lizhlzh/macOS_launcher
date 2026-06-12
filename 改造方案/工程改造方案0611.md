```
你现在要系统性重构并修复 macOS_launcher / Luma 项目。要求优先使用 macOS 原生能力，不引入第三方依赖。不要写 Demo 级代码，按真实 macOS 产品工程组织代码。

当前项目地址：
https://github.com/lizhlzh/macOS_launcher

当前项目是 Swift Package executable target，源码位于 Sources/MacOSLauncher。短期不要强行迁移到 .xcodeproj，先保留 SwiftPM 构建方式，但将源码目录整理成更接近真实 macOS App 工程的结构。

一、目录结构调整

将 Sources/MacOSLauncher 逐步整理为以下结构；如一次性改名 Sources/Luma 风险较大，可以先保持 Sources/MacOSLauncher，只调整内部目录：

Sources/Luma/
  App/
    LumaApp.swift
    AppDelegate.swift
    AppLifecycleCoordinator.swift
    AppCompositionRoot.swift
    MainMenuBuilder.swift

  Resources/
    Info.plist
    Assets.xcassets/
    Localizable.xcstrings

  Shared/
    Models/
    Errors/
    Utilities/
    Extensions/

  Services/
    ApplicationScanning/
    ApplicationLaunching/
    Cache/
    Preferences/
    HotKey/
    LoginItem/
    Permissions/
    Logging/

  Features/
    Launcher/
      State/
      Window/
      UI/
        LauncherRootView.swift
        Header/
        Pager/
        Tile/
        Folder/
        Menus/
    Settings/

Tests/
  LumaTests/

重点：拆分 Sources/MacOSLauncher/Features/LauncherUI/LauncherViews.swift。这个文件过大，不利于维护。

拆分建议：
- LauncherRootView.swift
- Header/HeaderButton.swift
- Header/SearchTextField.swift
- Header/VerticallyCenteredTextFieldCell.swift
- Pager/LauncherPagerView.swift
- Pager/LauncherPagerDelegate.swift
- Pager/PageDotsView.swift
- Pager/LauncherGridMetrics.swift
- Tile/LauncherTileView.swift
- Tile/LauncherTileViewDelegate.swift
- Folder/FolderOverlayView.swift
- Folder/FolderOverlayTileView.swift
- Folder/FolderIconRenderer.swift
- Menus/ClosureMenuItem.swift
- Shared/Extensions/NSView+LauncherHitTesting.swift

二、修复中文 App 显示英文名

问题文件：
Sources/MacOSLauncher/Services/ApplicationScanner/ApplicationScanner.swift

当前 localizedDisplayName(for:at:) 优先返回 Bundle.localizedInfoDictionary / infoDictionary，导致中文系统下微信等 App 显示英文名。

要求：
1. 新增 ApplicationDisplayNameResolver。
2. 优先使用 url.resourceValues(forKeys: [.localizedNameKey]).localizedName。
3. 其次使用 FileManager.default.displayName(atPath:)。
4. 再兜底 Bundle.localizedInfoDictionary["CFBundleDisplayName"]、Bundle.localizedInfoDictionary["CFBundleName"]、Bundle.infoDictionary。
5. 去掉 .app 后缀。
6. 修改 appendApp 使用 ApplicationDisplayNameResolver.displayName(for:bundle:)。

验收：
- 微信、企业微信、腾讯会议、网易云音乐等中文 App 优先显示中文名称。

三、修复顶部按钮无法点击

问题文件：
Sources/MacOSLauncher/Features/LauncherUI/LauncherViews.swift

要求：
1. LauncherRootView.hitTest 中先命中顶部控制按钮，再命中 searchField。
2. 避免搜索框 frame 覆盖按钮区域。
3. headerWidth 最小值提高到 960，或在空间不足时让 sort/layout 按钮只显示图标。
4. HeaderButton 保持原生 target/action，不引入 SwiftUI 包装。

验收：
- Sort、Layout、Filter、Edit、Folder、Rescan、Close 均可点击。
- 搜索框聚焦、输入、有搜索结果、无搜索结果状态下按钮仍可点击。

四、修复点击 App 命中整体下移一行

问题：
点击第 2 行某个 App，实际打开第 3 行同列 App。不是启动串行，而是 Tile 命中坐标错位。

要求：
1. 修改 LauncherPagerView.hitTest，不要再通过 activeTileViews.reversed() + view.convert(point, from:) 手动判断命中。
2. 改为：
   - 将 point 转换到 contentView；
   - 调用 contentView.hitTest(contentPoint)；
   - 从命中的子视图向上查找 LauncherTileView。
3. 新增 NSView.enclosingLauncherTileView 扩展。
4. 修改 LauncherTileView.hitTest，整个 bounds 都可点击，不要只判断 iconHitFrame。

示例：

override func hitTest(_ point: NSPoint) -> NSView? {
    guard bounds.contains(point) else {
        return nil
    }

    if isInteractionSuspended {
        return self
    }

    let contentPoint = contentView.convert(point, from: self)
    guard let hitView = contentView.hitTest(contentPoint) else {
        return nil
    }

    return hitView.enclosingLauncherTileView
}

extension NSView {
    var enclosingLauncherTileView: LauncherTileView? {
        var current: NSView? = self
        while let view = current {
            if let tileView = view as? LauncherTileView {
                return tileView
            }
            current = view.superview
        }
        return nil
    }
}

LauncherTileView.hitTest 改为：

override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(point) ? self : nil
}

验收：
- 点击第 1、2、3、4 行任意 App，打开的必须是视觉上对应位置的 App。
- 点击标题区域也能打开该 App。
- 搜索结果页、分页后、不同 rows/columns 布局下都不能出现错位。

五、修复长按进入排序模式

当前 LauncherTileView.mouseDown 已有 0.42 秒长按逻辑，但由于 hitTest 只认 iconHitFrame 且命中错位，导致长按不稳定。

要求：
1. 保留现有长按逻辑。
2. 依赖 LauncherTileView.hitTest 改为整个 bounds 可点击。
3. 长按后调用 tileViewDidRequestEditing，再进入 store.beginEditing()。
4. 编辑状态下显示可拖动标识。

验收：
- 长按任意 App tile 约 0.4 秒进入编辑模式。
- 点标题区域长按也能进入编辑模式。
- 顶部 Edit 按钮仍可进入/退出编辑模式。

六、修复拖动排序

当前 Store 层已有 beginDraggingTile 和 previewMoveTile。问题主要在拖拽目标识别。

要求：
1. 修改 tile(atDraggingLocation:)。
2. 不要继续复用 interactiveTile 的手动坐标判断。
3. 基于 contentView.hitTest 找真实拖拽目标。
4. 保留搜索状态下不允许排序的逻辑。

建议实现：

private func tile(atDraggingLocation location: NSPoint) -> LauncherTileView? {
    let localPoint = convert(location, from: nil)
    let contentPoint = contentView.convert(localPoint, from: self)
    return contentView.hitTest(contentPoint)?.enclosingLauncherTileView
}

如实测 sender.draggingLocation 已经是当前 view 坐标，则改成：

private func tile(atDraggingLocation location: NSPoint) -> LauncherTileView? {
    let contentPoint = contentView.convert(location, from: self)
    return contentView.hitTest(contentPoint)?.enclosingLauncherTileView
}

验收：
- 进入编辑模式后拖动 App 可以改变顺序。
- 拖动结束后顺序保存。
- 退出并重新打开 App，顺序仍保留。
- 搜索状态下不能排序。

七、实现 App 拖到已有文件夹

当前已有 store.addApp(draggedID, to: folder.id)，保留并修复命中后验证。

验收：
- App 拖到已有文件夹，App 加入文件夹。
- 原顶层 App 消失。
- 打开文件夹可以看到该 App。

八、实现 App 拖到 App 创建文件夹

当前 App 拖到 App 只会排序，不会创建文件夹。需要补完整业务。

修改 LauncherStore：
新增：

func createFolder(containingAppIDs appIDs: [String]) {
    var seen = Set<String>()
    let uniqueIDs = appIDs.filter { id in
        guard app(withID: id) != nil else { return false }
        return seen.insert(id).inserted
    }

    guard uniqueIDs.count >= 2 else {
        return
    }

    createFolder(named: nil, containing: uniqueIDs)
}

修改 LauncherTileViewDelegate 的 performDropWith：

func tileView(_ view: LauncherTileView, performDropWith draggedID: String) -> Bool {
    defer {
        dropTargetID = nil
        store.endDraggingTile(commit: true)
    }

    guard draggedID != view.tileID else {
        return false
    }

    if let folder = view.tile.folder, draggedID.hasPrefix("app:") {
        store.addApp(draggedID, to: folder.id)
        return true
    }

    if draggedID.hasPrefix("app:"),
       view.tile.app != nil {
        store.createFolder(containingAppIDs: [draggedID, view.tileID])
        return true
    }

    updateDropTarget(draggedID: draggedID, target: view)
    return true
}

第一阶段采用简化规则：
- hover 经过 App 可以继续排序预览；
- drop 到 App 就创建文件夹。

后续再优化为：
- drop 到目标中心区域创建文件夹；
- drop 到边缘区域排序。

验收：
- App A 拖到 App B，创建新文件夹。
- 新文件夹包含 App A 和 App B。
- App A 和 App B 不再出现在顶层。
- 文件夹出现在顶层。
- 文件夹名称唯一。

九、减少 UI 动画导致的交互阻塞

要求：
1. 搜索结果重排不应 suspendInteraction。
2. 普通 reload(animated:) 中可以减少或移除 suspendInteraction。
3. 分页动画可以保留短暂停止交互。
4. 不要因为动画导致点击、长按、拖拽被吞掉。

验收：
- 搜索后立即点击 App 不应点不动。
- 排序动画过程中不应导致后续点击串位。

十、测试

新增测试：
- ApplicationDisplayNameResolverTests
- LauncherStoreFolderTests
- TileOrderMoverTests

至少覆盖：
1. 中文显示名优先；
2. .app 后缀去除；
3. App 拖到 App 创建文件夹；
4. App 加入已有文件夹；
5. 拖动排序更新 tileOrder；
6. 无效 appID 不应破坏状态。

十一、最终验收清单

手动验证：
1. swift build 成功。
2. scripts/build-app.sh 成功。
3. 启动 Luma 成功。
4. 中文 App 显示中文。
5. 顶部按钮全部可点击。
6. 点击每一行 App 不再错位。
7. 长按 App 进入编辑模式。
8. 拖动 App 可以排序。
9. App 拖到已有文件夹可以加入。
10. App 拖到 App 可以创建文件夹。
11. 搜索状态下不允许排序。
12. 改 rows/columns 后点击和拖拽仍正常。
13. 翻页后点击和拖拽仍正常。
14. 重启 Luma 后排序和文件夹状态仍保留。

请按小步提交方式修改：
Phase 1：目录拆分，不改变行为；
Phase 2：中文 App 名称修复；
Phase 3：Header 按钮命中修复；
Phase 4：Tile/Pager hitTest 修复；
Phase 5：拖拽排序修复；
Phase 6：App-to-App 创建文件夹；
Phase 7：测试与验收日志清理。

每个 Phase 修改后输出：
- 修改了哪些文件；
- 为什么这么改；
- 风险点；
- 手动验收步骤。
```