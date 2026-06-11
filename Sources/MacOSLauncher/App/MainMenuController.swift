import AppKit

/// 构建标准 macOS 菜单栏，并向上发送应用级操作意图。
///
/// 调用方向：菜单动作 -> 闭包 -> `AppLifecycleCoordinator`。
@MainActor
final class MainMenuController: NSObject {
    var onShowLauncher: (() -> Void)?
    var onHideLauncher: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onRescan: (() -> Void)?
    var onFocusSearch: (() -> Void)?
    var onRevealLogs: (() -> Void)?

    /// 使用 Luma 的菜单层级替换 `NSApp.mainMenu`。
    func install() {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(viewMenuItem())
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private func appMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "Luma")
        menu.addItem(withTitle: "About Luma", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item("Settings…", action: #selector(showSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Luma", action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        root.submenu = menu
        return root
    }

    private func fileMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "File")
        menu.addItem(item("Open Launcher", action: #selector(showLauncher), key: "o"))
        menu.addItem(item("Rescan Applications", action: #selector(rescan), key: "r"))
        root.submenu = menu
        return root
    }

    private func editMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Find", action: #selector(focusSearch), key: "f"))
        root.submenu = menu
        return root
    }

    private func viewMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        root.submenu = NSMenu(title: "View")
        return root
    }

    private func windowMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Hide Launcher", action: #selector(hideLauncher), key: "w"))
        root.submenu = menu
        return root
    }

    private func helpMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "Help")
        menu.addItem(item("Reveal Logs", action: #selector(revealLogs), key: ""))
        root.submenu = menu
        return root
    }

    /// 创建并绑定一个标准菜单项。
    ///
    /// - Parameters:
    ///   - title: 菜单项显示文本。
    ///   - action: 用户选择菜单项时发送的 Selector。
    ///   - key: 不含 Command 修饰键的快捷键字符；空字符串表示无快捷键。
    ///   - target: 动作接收对象；为 `nil` 时使用当前菜单控制器。
    /// - Returns: 已配置 target/action 的菜单项。
    private func item(
        _ title: String,
        action: Selector,
        key: String,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    @objc private func showLauncher() { onShowLauncher?() }
    @objc private func hideLauncher() { onHideLauncher?() }
    @objc private func showSettings() { onShowSettings?() }
    @objc private func rescan() { onRescan?() }
    @objc private func focusSearch() { onFocusSearch?() }
    @objc private func revealLogs() { onRevealLogs?() }
}
