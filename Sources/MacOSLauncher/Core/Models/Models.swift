import Foundation

/// 可由用户恢复、并能直接展示在启动器 UI 中的错误。
enum LauncherRecoverableError: Equatable {
    case applicationScan(String)
    case preferences(String)
    case cache(String)

    var message: String {
        switch self {
        case let .applicationScan(message), let .preferences(message), let .cache(message):
            message
        }
    }
}

/// 描述启动器内容处于就绪、刷新、空数据或失败状态。
enum LauncherContentState: Equatable {
    case ready
    case refreshing
    case empty
    case failed(LauncherRecoverableError)
}

/// 控制 Tile 使用用户自定义顺序还是应用本地化名称排序。
enum SortMode: String, Codable, CaseIterable, Identifiable {
    case custom
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .custom:
            "Custom"
        case .name:
            "A-Z"
        }
    }
}

/// 在不修改存储数据的前提下筛选可见、隐藏或全部应用。
enum AppFilterMode: String, Codable, CaseIterable, Identifiable {
    case visibleOnly
    case all
    case hiddenOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visibleOnly:
            "Visible Apps"
        case .all:
            "All Apps"
        case .hiddenOnly:
            "Hidden Apps"
        }
    }
}

/// 已安装应用包的稳定、可序列化元数据。
struct LauncherAppInfo: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let bundleIdentifier: String?
    let path: String
}

/// 包含应用标识的用户自定义文件夹。
struct LauncherFolder: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var itemIDs: [String]

    var tileID: String {
        "folder:\(id)"
    }
}

/// 经过范围校验的网格行列数，供分页和布局计算使用。
struct LauncherGridLayout: Codable, Hashable, Sendable {
    static let allowedRows = 3...7
    static let allowedColumns = 4...10
    static let `default` = LauncherGridLayout(rows: 5, columns: 7)

    var rows: Int
    var columns: Int

    /// 创建网格布局，并将行列数限制在允许范围内。
    ///
    /// - Parameters:
    ///   - rows: 每页网格行数。
    ///   - columns: 每页网格列数。
    init(rows: Int, columns: Int) {
        self.rows = min(max(rows, Self.allowedRows.lowerBound), Self.allowedRows.upperBound)
        self.columns = min(max(columns, Self.allowedColumns.lowerBound), Self.allowedColumns.upperBound)
    }

    var itemsPerPage: Int {
        rows * columns
    }

    var title: String {
        "\(rows) x \(columns)"
    }
}

/// 持久化到 `preferences.json` 的用户可配置启动器状态。
struct LauncherPreferences: Codable {
    var sortMode: SortMode
    var tileOrder: [String]
    var folders: [LauncherFolder]
    var gridLayout: LauncherGridLayout
    var hiddenAppIDs: [String]
    var appFilterMode: AppFilterMode

    static let empty = LauncherPreferences(
        sortMode: .custom,
        tileOrder: [],
        folders: [],
        gridLayout: .default,
        hiddenAppIDs: [],
        appFilterMode: .visibleOnly
    )

    /// 创建完整用户偏好快照。
    ///
    /// - Parameters:
    ///   - sortMode: Tile 排序模式。
    ///   - tileOrder: 用户自定义的顶层 Tile 顺序。
    ///   - folders: 用户创建的文件夹列表。
    ///   - gridLayout: 分页网格行列配置。
    ///   - hiddenAppIDs: 被用户隐藏的应用标识。
    ///   - appFilterMode: 当前应用可见性筛选模式。
    init(
        sortMode: SortMode,
        tileOrder: [String],
        folders: [LauncherFolder],
        gridLayout: LauncherGridLayout,
        hiddenAppIDs: [String],
        appFilterMode: AppFilterMode
    ) {
        self.sortMode = sortMode
        self.tileOrder = tileOrder
        self.folders = folders
        self.gridLayout = gridLayout
        self.hiddenAppIDs = hiddenAppIDs
        self.appFilterMode = appFilterMode
    }

    /// 从持久化数据解码偏好，并为旧版本缺失字段提供默认值。
    ///
    /// - Parameter decoder: Swift `Codable` 解码器。
    /// - Throws: 字段存在但内容无法解码时抛出解码错误。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sortMode = try container.decodeIfPresent(SortMode.self, forKey: .sortMode) ?? .custom
        tileOrder = try container.decodeIfPresent([String].self, forKey: .tileOrder) ?? []
        folders = try container.decodeIfPresent([LauncherFolder].self, forKey: .folders) ?? []
        gridLayout = try container.decodeIfPresent(LauncherGridLayout.self, forKey: .gridLayout) ?? .default
        hiddenAppIDs = try container.decodeIfPresent([String].self, forKey: .hiddenAppIDs) ?? []
        appFilterMode = try container.decodeIfPresent(AppFilterMode.self, forKey: .appFilterMode) ?? .visibleOnly
    }
}

/// 最近一次成功扫描缓存，用于启动时立即展示内容。
struct ApplicationCache: Codable {
    static let currentSchemaVersion = 1

    var applications: [LauncherAppInfo]
    var lastScannedAt: Date
    var schemaVersion: Int
}

/// 应用发现过程中产生的非致命路径级警告。
struct ApplicationScanWarning: Sendable {
    let path: String
    let message: String
}

/// 完整扫描输出：可用应用列表和可恢复警告。
struct ApplicationScanResult: Sendable {
    let applications: [LauncherAppInfo]
    let warnings: [ApplicationScanWarning]
}

/// 将顶层应用和文件夹统一后的展示模型。
///
/// 数据方向：`LauncherStore` 创建 Tile -> `LauncherPagerView` 渲染。
struct LauncherTile: Identifiable, Hashable {
    enum Kind: Hashable {
        case app(LauncherAppInfo)
        case folder(LauncherFolder, [LauncherAppInfo])
    }

    let id: String
    let title: String
    let kind: Kind

    var folder: LauncherFolder? {
        if case let .folder(folder, _) = kind {
            folder
        } else {
            nil
        }
    }

    var app: LauncherAppInfo? {
        if case let .app(app) = kind {
            app
        } else {
            nil
        }
    }
}
