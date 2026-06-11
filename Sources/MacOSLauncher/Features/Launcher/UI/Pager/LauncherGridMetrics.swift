import Foundation

/// Geometry derived from the pager size and validated grid preferences.
struct LauncherGridMetrics {
    let columns: Int
    let rows: Int
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let iconSize: CGFloat
    let titleHeight: CGFloat
    let iconTitleSpacing: CGFloat
    let tileVerticalPadding: CGFloat
    let rowSpacing: CGFloat
    let columnSpacing: CGFloat
    let leadingInset: CGFloat

    init(size: CGSize, layout: LauncherGridLayout) {
        columns = layout.columns
        rows = layout.rows
        rowSpacing = 10
        columnSpacing = 14

        let availableWidth = max(360, size.width)
        let availableHeight = max(260, size.height)
        let rawTileWidth = (availableWidth - CGFloat(columns - 1) * columnSpacing)
            / CGFloat(columns)
        let rawTileHeight = (availableHeight - CGFloat(rows - 1) * rowSpacing)
            / CGFloat(rows)

        tileWidth = floor(min(260, max(112, rawTileWidth)))
        tileHeight = floor(min(166, max(88, rawTileHeight)))
        iconSize = floor(min(108, max(46, min(tileWidth - 34, tileHeight - 48))))
        titleHeight = floor(min(34, max(22, tileHeight - iconSize - 24)))
        iconTitleSpacing = min(10, max(4, tileHeight - iconSize - titleHeight - 16))
        tileVerticalPadding = min(
            10,
            max(6, (tileHeight - iconSize - titleHeight - iconTitleSpacing) / 2)
        )

        let gridWidth = CGFloat(columns) * tileWidth
            + CGFloat(columns - 1) * columnSpacing
        leadingInset = max(0, floor((availableWidth - gridWidth) / 2))
    }

    var itemsPerPage: Int {
        rows * columns
    }
}
