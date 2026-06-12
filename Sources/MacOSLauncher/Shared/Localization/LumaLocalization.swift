import Foundation

enum L10n {
    static var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    enum Key {
        case searchPlaceholder
        case sortCustom
        case sortName
        case filterVisible
        case filterAll
        case filterHidden
        case layoutRows
        case layoutColumns
        case layoutDefault
        case appsPerPage(Int)
        case rowCount(Int)
        case columnCount(Int)
        case sortTooltip
        case layoutTooltip
        case filterTooltip
        case editTooltip
        case doneEditingTooltip
        case newFolder
        case rescan
        case close
        case refreshingApplications
        case noApplicationsFound
        case open
        case showInFinder
        case hideApp
        case unhideApp
        case moveToFolder
        case rename
        case renameFolder
        case deleteFolder
        case create
        case cancel
        case removeFromFolder
        case noAppsInFolder
        case launcherMenuOpen
        case launcherMenuHide
        case menuRescan
        case menuSettings
        case menuRevealLogs
        case settingsTitle
        case general
        case hotKey
        case permissions
        case appearance
        case advanced
        case launchAtLogin
        case openLauncher
        case openAccessibilitySettings
        case openInputMonitoringSettings
        case generalDescription
        case hotKeyDescription
        case permissionsDescription
        case appearanceDescription
        case advancedDescription
        case accessibilityGranted(Bool)
        case inputMonitoringGranted(Bool)
        case statusGranted
        case statusNotGranted
    }

    static func text(_ key: Key) -> String {
        switch key {
        case .searchPlaceholder:
            isChinese ? "搜索 App" : "Search apps"
        case .sortCustom:
            isChinese ? "自定义" : "Custom"
        case .sortName:
            isChinese ? "名称" : "A-Z"
        case .filterVisible:
            isChinese ? "可见应用" : "Visible Apps"
        case .filterAll:
            isChinese ? "全部应用" : "All Apps"
        case .filterHidden:
            isChinese ? "已隐藏应用" : "Hidden Apps"
        case .layoutRows:
            isChinese ? "行数" : "Rows"
        case .layoutColumns:
            isChinese ? "列数" : "Columns"
        case .layoutDefault:
            isChinese ? "默认 5 × 7" : "Default 5 × 7"
        case let .appsPerPage(count):
            isChinese ? "每页 \(count) 个应用" : "\(count) apps per page"
        case let .rowCount(count):
            isChinese ? "\(count) 行" : "\(count) rows"
        case let .columnCount(count):
            isChinese ? "\(count) 列" : "\(count) columns"
        case .sortTooltip:
            isChinese ? "排序" : "Sort"
        case .layoutTooltip:
            isChinese ? "布局" : "Layout"
        case .filterTooltip:
            isChinese ? "筛选应用" : "Filter Apps"
        case .editTooltip:
            isChinese ? "编辑" : "Edit"
        case .doneEditingTooltip:
            isChinese ? "完成" : "Done Editing"
        case .newFolder:
            isChinese ? "新建文件夹" : "New Folder"
        case .rescan:
            isChinese ? "重新扫描" : "Rescan Applications"
        case .close:
            isChinese ? "关闭" : "Close"
        case .refreshingApplications:
            isChinese ? "正在重新扫描应用" : "Refreshing Applications"
        case .noApplicationsFound:
            isChinese ? "未找到应用。请尝试重新扫描。" : "No applications found. Use Rescan Applications to try again."
        case .open:
            isChinese ? "打开" : "Open"
        case .showInFinder:
            isChinese ? "在 Finder 中显示" : "Show in Finder"
        case .hideApp:
            isChinese ? "隐藏应用" : "Hide App"
        case .unhideApp:
            isChinese ? "取消隐藏" : "Unhide App"
        case .moveToFolder:
            isChinese ? "移入文件夹" : "Move to Folder"
        case .rename:
            isChinese ? "重命名" : "Rename"
        case .renameFolder:
            isChinese ? "重命名文件夹" : "Rename Folder"
        case .deleteFolder:
            isChinese ? "删除文件夹" : "Delete Folder"
        case .create:
            isChinese ? "创建" : "Create"
        case .cancel:
            isChinese ? "取消" : "Cancel"
        case .removeFromFolder:
            isChinese ? "从文件夹移除" : "Remove from Folder"
        case .noAppsInFolder:
            isChinese ? "这个文件夹中没有应用" : "No apps in this folder"
        case .launcherMenuOpen:
            isChinese ? "打开启动台" : "Open Launcher"
        case .launcherMenuHide:
            isChinese ? "隐藏启动台" : "Hide Launcher"
        case .menuRescan:
            isChinese ? "重新扫描应用" : "Rescan Applications"
        case .menuSettings:
            isChinese ? "设置…" : "Settings…"
        case .menuRevealLogs:
            isChinese ? "显示日志" : "Reveal Logs"
        case .settingsTitle:
            isChinese ? "Luma 设置" : "Luma Settings"
        case .general:
            isChinese ? "通用" : "General"
        case .hotKey:
            isChinese ? "快捷键" : "Hot Key"
        case .permissions:
            isChinese ? "权限" : "Permissions"
        case .appearance:
            isChinese ? "外观" : "Appearance"
        case .advanced:
            isChinese ? "高级" : "Advanced"
        case .launchAtLogin:
            isChinese ? "登录时启动 Luma" : "Launch Luma at login"
        case .openLauncher:
            isChinese ? "打开启动台" : "Open Launcher"
        case .openAccessibilitySettings:
            isChinese ? "打开辅助功能设置" : "Open Accessibility Settings"
        case .openInputMonitoringSettings:
            isChinese ? "打开输入监控设置" : "Open Input Monitoring Settings"
        case .generalDescription:
            isChinese ? "隐藏启动台后，Luma 仍会继续运行。按 Command-Q 可退出应用。" : "Luma remains running when the Launcher is hidden. Command-Q quits the app."
        case .hotKeyDescription:
            isChinese ? "可在任意应用中使用全局快捷键。" : "Use the global shortcut from any application."
        case .permissionsDescription:
            isChinese ? "这些权限是可选的。即使未授予，Luma 也会继续工作。" : "Permissions are optional. Luma keeps working when they are unavailable."
        case .appearanceDescription:
            isChinese ? "Luma 会跟随系统外观和辅助功能对比度设置。" : "Luma follows the system appearance and accessibility contrast settings."
        case .advancedDescription:
            isChinese ? "可刷新本地应用索引，或查看诊断日志。" : "Refresh the local application index or inspect diagnostic logs."
        case let .accessibilityGranted(granted):
            isChinese ? "辅助功能：\(text(granted ? .statusGranted : .statusNotGranted))" : "Accessibility: \(text(granted ? .statusGranted : .statusNotGranted))"
        case let .inputMonitoringGranted(granted):
            isChinese ? "输入监控：\(text(granted ? .statusGranted : .statusNotGranted))" : "Input Monitoring: \(text(granted ? .statusGranted : .statusNotGranted))"
        case .statusGranted:
            isChinese ? "已授权" : "Granted"
        case .statusNotGranted:
            isChinese ? "未授权" : "Not granted"
        }
    }
}
