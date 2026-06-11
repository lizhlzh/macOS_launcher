import AppKit

/// 管理启动器 Panel 生命周期、屏幕选择和显示/隐藏动画。
///
/// 调用方向：
/// `AppLifecycleCoordinator` -> `LauncherController` -> `LauncherPanel`.
/// 面板输入回调再经控制器流回 `LauncherStore`。
@MainActor
final class LauncherController {
    let store: LauncherStore

    private var panel: LauncherPanel?
    private var isAnimating = false

    /// 创建启动器窗口控制器。
    ///
    /// - Parameter store: 启动器业务状态。
    init(store: LauncherStore) {
        self.store = store
    }

    /// 启动器面板当前是否可见。
    var isVisible: Bool {
        panel?.isVisible == true
    }

    /// 在既有显示和隐藏动画路径之间切换。
    func toggle() {
        isVisible ? hide() : show()
    }

    /// 将离散翻页请求转发给业务状态。
    ///
    /// - Parameter offset: 页码偏移量；正数向后，负数向前。
    func changePage(by offset: Int) {
        store.changePage(by: offset)
    }

    /// 优先结束编辑模式；未处于编辑状态时才隐藏启动器。
    func handleEscape() {
        if store.isEditing {
            store.endEditing()
        } else {
            hide()
        }
    }

    /// 将第一响应者焦点转发给根视图搜索框。
    func focusSearch() {
        (panel?.contentView as? LauncherRootView)?.focusSearch()
    }

    /// 将 Panel 放到活动屏幕，并执行既有入场动画。
    ///
    /// 调用方向：协调器/菜单/快捷键/手势 -> Controller -> Panel + 根视图。
    func show() {
        guard !isAnimating else {
            return
        }

        if panel == nil {
            panel = makePanel()
        }

        guard let panel else {
            return
        }

        let screenFrame = targetScreen()?.frame ?? .zero
        panel.setFrame(screenFrame, display: true)
        panel.alphaValue = 0

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        store.prepareForPresentation()
        let rootView = panel.contentView as? LauncherRootView

        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.78, 0.22, 1)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isAnimating = false
            }
        }
        DispatchQueue.main.async {
            rootView?.playPresentationAnimation()
        }
    }

    /// 执行既有淡出动画，完成后将 Panel 移出屏幕。
    func hide() {
        guard let panel, panel.isVisible, !isAnimating else {
            return
        }

        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor in
                panel?.orderOut(nil)
                panel?.alphaValue = 1
                self?.isAnimating = false
            }
        }
    }

    /// 只创建并连接一次 Panel，后续展示复用同一视图层级。
    private func makePanel() -> LauncherPanel {
        let initialFrame = targetScreen()?.frame ?? .zero
        let panel = LauncherPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.onEscape = { [weak self] in
            self?.handleEscape()
        }
        panel.onPageGesture = { [weak self] offset in
            self?.changePage(by: offset)
        }
        panel.onPageScroll = { [weak self] deltaX, phase, pageWidth in
            guard let self else {
                return
            }

            switch phase {
            case .began:
                self.store.beginPageDrag()
            case .changed:
                self.store.updatePageDrag(deltaX: deltaX, pageWidth: pageWidth)
            case .ended:
                self.store.finishPageDrag(pageWidth: pageWidth)
            }
        }

        let rootView = LauncherRootView(
            frame: panel.contentRect(forFrameRect: panel.frame),
            store: store,
            onClose: { [weak self] in
                self?.hide()
            },
            onEscape: { [weak self] in
                self?.handleEscape()
            }
        )
        panel.contentView = rootView
        return panel
    }

    /// 依次选择鼠标所在屏幕、Key Window 屏幕和 macOS 主屏幕。
    ///
    /// - Returns: 最适合展示启动器的屏幕；无屏幕时返回 `nil`。
    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return mouseScreen
        }
        if let keyWindowScreen = NSApp.keyWindow?.screen {
            return keyWindowScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}

/// 将键盘和触控板水平滚动事件转换为启动器意图的无边框 Panel。
///
/// 手势方向：
/// `NSEvent.scrollWheel` -> 过滤后的位移 -> Controller 回调
/// -> Store 拖动状态 -> Pager frame origin。
final class LauncherPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onPageGesture: ((Int) -> Void)?
    var onPageScroll: ((CGFloat, PageScrollPhase, CGFloat) -> Void)?
    private var isTrackingHorizontalScroll = false
    private var finishScrollWorkItem: DispatchWorkItem?
    private var horizontalScrollAccumulated: CGFloat = 0
    private var horizontalScrollDirection: CGFloat = 0

    private let horizontalScrollNoiseFloor: CGFloat = 0.45
    private let horizontalScrollDirectionThreshold: CGFloat = 18
    private let horizontalScrollReverseDamping: CGFloat = 0.16
    private let horizontalScrollFinishDelay: TimeInterval = 0.045

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            onEscape?()
            return
        }
        switch event.keyCode {
        case 53:
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }

    override func swipe(with event: NSEvent) {
        // 水平分页由 scrollWheel 驱动，使页面持续跟随手指，
        // 并在真实手势结束后才执行归位。
    }

    /// 过滤垂直和惯性输入，并连续发送精确水平位移。
    ///
    /// 噪声阈值、方向锁定、反向阻尼和结束延迟属于当前手势体验参数，
    /// 修改时必须进行完整交互验证。
    ///
    /// - Parameter event: AppKit 传入的滚轮或触控板事件。
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
            super.scrollWheel(with: event)
            return
        }

        if !event.momentumPhase.isEmpty {
            finishHorizontalScroll()
            return
        }

        if event.phase.contains(.began) {
            beginHorizontalScroll()
        }

        if event.scrollingDeltaX != 0 {
            if !isTrackingHorizontalScroll {
                beginHorizontalScroll()
            }

            let adjustedDelta = adjustedHorizontalDelta(from: event)
            if adjustedDelta != 0 {
                onPageScroll?(adjustedDelta, .changed, frame.width)
            }
            if event.phase.isEmpty {
                scheduleScrollFinishFallback()
            } else {
                finishScrollWorkItem?.cancel()
                finishScrollWorkItem = nil
            }
        }

        if event.phase.contains(.ended)
            || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended)
            || event.momentumPhase.contains(.cancelled) {
            finishHorizontalScroll()
        }
    }

    /// 重置单次手势状态，并通知 Store 开始交互式分页。
    private func beginHorizontalScroll() {
        finishScrollWorkItem?.cancel()
        finishScrollWorkItem = nil
        isTrackingHorizontalScroll = true
        horizontalScrollAccumulated = 0
        horizontalScrollDirection = 0
        onPageScroll?(0, .began, frame.width)
    }

    /// 缩放精确位移、过滤噪声，并对小幅反向移动进行阻尼。
    ///
    /// - Parameter event: 当前滚动事件。
    /// - Returns: 调整后的水平位移；噪声事件返回 `0`。
    private func adjustedHorizontalDelta(from event: NSEvent) -> CGFloat {
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 2.05 : 1.20
        var delta = event.scrollingDeltaX * scale

        guard abs(delta) >= horizontalScrollNoiseFloor else {
            return 0
        }

        if horizontalScrollDirection == 0 {
            horizontalScrollAccumulated += delta
            if abs(horizontalScrollAccumulated) >= horizontalScrollDirectionThreshold {
                horizontalScrollDirection = horizontalScrollAccumulated > 0 ? 1 : -1
            }
            return delta
        }

        let incomingDirection: CGFloat = delta > 0 ? 1 : -1
        if incomingDirection != horizontalScrollDirection
            && abs(delta) < horizontalScrollDirectionThreshold {
            delta *= horizontalScrollReverseDamping
        }

        horizontalScrollAccumulated += delta
        if abs(horizontalScrollAccumulated) < horizontalScrollDirectionThreshold * 0.55 {
            horizontalScrollDirection = 0
        }

        return delta
    }

    /// 为不发送 phase 的设备补充手势结束事件。
    private func scheduleScrollFinishFallback() {
        finishScrollWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.finishHorizontalScroll()
        }
        finishScrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + horizontalScrollFinishDelay, execute: workItem)
    }

    /// 确保单次手势只结束一次，并请求 Store 完成页面归位。
    private func finishHorizontalScroll() {
        guard isTrackingHorizontalScroll else {
            return
        }

        finishScrollWorkItem?.cancel()
        finishScrollWorkItem = nil
        isTrackingHorizontalScroll = false
        horizontalScrollAccumulated = 0
        horizontalScrollDirection = 0
        onPageScroll?(0, .ended, frame.width)
    }
}

/// `LauncherPanel` 向 Controller 发送的标准化滚动阶段。
enum PageScrollPhase {
    case began
    case changed
    case ended
}
