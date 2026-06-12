import AppKit

/// 管理常驻原生设置窗口及其五个设置页面。
///
/// 调用方向：
/// `AppLifecycleCoordinator` 展示此控制器；控件直接调用权限/登录项服务，
/// 或向上发送重新扫描和显示启动器意图。
@MainActor
final class SettingsWindowController: NSWindowController {
    var onRescan: (() -> Void)?
    var onShowLauncher: (() -> Void)?

    private let environment: AppEnvironment
    private let hotKeyStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let permissionStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let loginItemCheckbox = NSButton(checkboxWithTitle: L10n.text(.launchAtLogin), target: nil, action: nil)

    /// 创建设置窗口。
    ///
    /// - Parameter environment: 提供权限、开机启动等系统服务的依赖容器。
    init(environment: AppEnvironment) {
        self.environment = environment
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.settingsTitle)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentViewController = makeTabs()
        refreshStatuses()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 显示窗口前刷新外部系统状态。
    ///
    /// - Parameter sender: 触发显示设置窗口的对象。
    override func showWindow(_ sender: Any?) {
        refreshStatuses()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    /// 将协调器的快捷键注册状态同步到“快捷键”页面。
    ///
    /// - Parameter error: 最近一次快捷键注册错误；为 `nil` 表示注册成功。
    func updateHotKeyStatus(error: HotKeyRegistrationError?) {
        hotKeyStatusLabel.stringValue = error?.localizedDescription
            ?? (L10n.isChinese ? "Control-Option-Space 已注册。" : "Control-Option-Space is registered.")
        hotKeyStatusLabel.textColor = error == nil ? .secondaryLabelColor : .systemRed
    }

    /// 一次性构建设置页面层级，后续只原地更新状态文本。
    private func makeTabs() -> NSTabViewController {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(tab(title: L10n.text(.general), symbol: "gearshape", view: generalView()))
        tabs.addTabViewItem(tab(title: L10n.text(.hotKey), symbol: "keyboard", view: hotKeyView()))
        tabs.addTabViewItem(tab(title: L10n.text(.permissions), symbol: "hand.raised", view: permissionsView()))
        tabs.addTabViewItem(tab(title: L10n.text(.appearance), symbol: "circle.lefthalf.filled", view: appearanceView()))
        tabs.addTabViewItem(tab(title: L10n.text(.advanced), symbol: "wrench.and.screwdriver", view: advancedView()))
        return tabs
    }

    /// 创建一个带 SF Symbol 图标的设置标签页。
    ///
    /// - Parameters:
    ///   - title: 标签页标题。
    ///   - symbol: SF Symbol 名称。
    ///   - view: 标签页承载的内容视图。
    /// - Returns: 可添加到 `NSTabViewController` 的标签项。
    private func tab(title: String, symbol: String, view: NSView) -> NSTabViewItem {
        let controller = NSViewController()
        controller.view = view
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    private func generalView() -> NSView {
        loginItemCheckbox.target = self
        loginItemCheckbox.action = #selector(toggleLoginItem)
        let openButton = NSButton(title: L10n.text(.openLauncher), target: self, action: #selector(openLauncher))
        return settingsView(
            title: L10n.text(.general),
            description: L10n.text(.generalDescription),
            controls: [loginItemCheckbox, openButton]
        )
    }

    private func hotKeyView() -> NSView {
        settingsView(
            title: L10n.text(.hotKey),
            description: L10n.text(.hotKeyDescription),
            controls: [hotKeyStatusLabel]
        )
    }

    private func permissionsView() -> NSView {
        let accessibility = NSButton(
            title: L10n.text(.openAccessibilitySettings),
            target: self,
            action: #selector(openAccessibilitySettings)
        )
        let input = NSButton(
            title: L10n.text(.openInputMonitoringSettings),
            target: self,
            action: #selector(openInputMonitoringSettings)
        )
        return settingsView(
            title: L10n.text(.permissions),
            description: L10n.text(.permissionsDescription),
            controls: [permissionStatusLabel, accessibility, input]
        )
    }

    private func appearanceView() -> NSView {
        settingsView(
            title: L10n.text(.appearance),
            description: L10n.text(.appearanceDescription),
            controls: []
        )
    }

    private func advancedView() -> NSView {
        let rescan = NSButton(title: L10n.text(.menuRescan), target: self, action: #selector(rescan))
        let logs = NSButton(title: L10n.text(.menuRevealLogs), target: self, action: #selector(revealLogs))
        return settingsView(
            title: L10n.text(.advanced),
            description: L10n.text(.advancedDescription),
            controls: [rescan, logs]
        )
    }

    /// 使用统一间距构建设置页内容。
    ///
    /// - Parameters:
    ///   - title: 页面主标题。
    ///   - description: 页面功能说明。
    ///   - controls: 按垂直顺序展示的控件和状态标签。
    /// - Returns: 完成 Auto Layout 约束的设置内容视图。
    private func settingsView(title: String, description: String, controls: [NSView]) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        let descriptionLabel = NSTextField(wrappingLabelWithString: description)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.preferredMaxLayoutWidth = 520
        for case let label as NSTextField in controls {
            label.preferredMaxLayoutWidth = 520
        }

        let stack = NSStackView(views: [titleLabel, descriptionLabel] + controls)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let view = NSView()
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
            descriptionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520)
        ])
        return view
    }

    /// 从系统服务读取当前开机启动和权限状态。
    private func refreshStatuses() {
        loginItemCheckbox.state = environment.loginItemManager.isEnabled ? .on : .off
        let status = environment.permissionManager.status
        permissionStatusLabel.stringValue =
            L10n.text(.accessibilityGranted(status.accessibilityGranted))
            + "\n"
            + L10n.text(.inputMonitoringGranted(status.inputMonitoringGranted))
    }

    @objc private func toggleLoginItem() {
        do {
            try environment.loginItemManager.setEnabled(loginItemCheckbox.state == .on)
        } catch {
            loginItemCheckbox.state = environment.loginItemManager.isEnabled ? .on : .off
            showError(error)
        }
    }

    @objc private func openLauncher() {
        onShowLauncher?()
    }

    @objc private func openAccessibilitySettings() {
        environment.permissionManager.openAccessibilitySettings()
    }

    @objc private func openInputMonitoringSettings() {
        environment.permissionManager.openInputMonitoringSettings()
    }

    @objc private func rescan() {
        onRescan?()
    }

    @objc private func revealLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: LumaEventLog.shared.path)
        ])
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
