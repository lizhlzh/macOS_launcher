import AppKit

/// 不可交互的轻量副本页，只用于首尾循环分页的视觉占位。
@MainActor
final class LauncherReplicaPageView: NSView {
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

        layoutSubtreeIfNeeded()
    }

    func clear() {
        subviews.forEach { $0.removeFromSuperview() }
    }
}

/// 只显示图标和标题的轻量副本 Tile，用于首尾循环分页时的视觉占位。
@MainActor
final class LauncherReplicaTileView: NSView {
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

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        LauncherTileVisualStyle.configureIconLayer(iconView.layer)
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.wraps = true
        titleLabel.cell?.usesSingleLineMode = false
        titleLabel.wantsLayer = true
        LauncherTileVisualStyle.configureTitleLayer(titleLabel.layer)
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
