import AppKit
import QuartzCore

/// A modal launcher overlay that displays and manages one folder.
@MainActor
final class FolderOverlayView: NSView {
    let folderID: String
    var onClose: (() -> Void)?
    var onLaunch: ((LauncherAppInfo) -> Void)?
    var onRename: ((LauncherFolder) -> Void)?

    private let store: LauncherStore
    private var folder: LauncherFolder
    private let panel = NSVisualEffectView()
    private let titleButton = NSButton()
    private let closeButton = NSButton()
    private let scrollView = NSScrollView()
    private let documentView = FlippedView()
    private let emptyStateLabel = NSTextField(labelWithString: L10n.text(.noAppsInFolder))
    private var appViews: [FolderOverlayTileView] = []

    override var isFlipped: Bool { true }

    init(frame: NSRect, folder: LauncherFolder, store: LauncherStore) {
        folderID = folder.id
        self.folder = folder
        self.store = store
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.24).cgColor

        panel.material = .popover
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor
        panel.layer?.cornerRadius = 32
        panel.layer?.cornerCurve = .continuous
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor.white.withAlphaComponent(0.13).cgColor
        panel.layer?.shadowColor = NSColor.black.cgColor
        panel.layer?.shadowOpacity = 0.12
        panel.layer?.shadowRadius = 28
        panel.layer?.shadowOffset = CGSize(width: 0, height: -12)
        addSubview(panel)

        titleButton.isBordered = false
        titleButton.font = .systemFont(ofSize: 25, weight: .semibold)
        titleButton.contentTintColor = .white
        titleButton.target = self
        titleButton.action = #selector(renameFolder)
        titleButton.setAccessibilityLabel("\(L10n.text(.renameFolder)) \(folder.name)")
        panel.addSubview(titleButton)

        closeButton.isBordered = false
        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: L10n.text(.close)
        )
        closeButton.contentTintColor = .white.withAlphaComponent(0.82)
        closeButton.target = self
        closeButton.action = #selector(closeOverlay)
        panel.addSubview(closeButton)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = documentView
        panel.addSubview(scrollView)

        emptyStateLabel.font = .systemFont(ofSize: 16, weight: .medium)
        emptyStateLabel.textColor = .white.withAlphaComponent(0.60)
        emptyStateLabel.alignment = .center
        emptyStateLabel.isHidden = true
        panel.addSubview(emptyStateLabel)
        reloadApps()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let panelSize = NSSize(
            width: 650,
            height: min(520, max(420, bounds.height - 180))
        )
        panel.frame = NSRect(
            x: floor((bounds.width - panelSize.width) / 2),
            y: floor((bounds.height - panelSize.height) / 2),
            width: panelSize.width,
            height: panelSize.height
        )
        titleButton.frame = NSRect(
            x: 26,
            y: 20,
            width: panel.bounds.width - 100,
            height: 38
        )
        closeButton.frame = NSRect(
            x: panel.bounds.width - 58,
            y: 20,
            width: 34,
            height: 34
        )
        scrollView.frame = NSRect(
            x: 22,
            y: 74,
            width: panel.bounds.width - 44,
            height: panel.bounds.height - 96
        )
        emptyStateLabel.frame = NSRect(
            x: 48,
            y: floor(panel.bounds.midY - 12),
            width: panel.bounds.width - 96,
            height: 24
        )
        layoutApps()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !panel.frame.contains(point) {
            onClose?()
        }
    }

    func update(folder: LauncherFolder) {
        self.folder = folder
        reloadApps()
    }

    private func reloadApps() {
        titleButton.title = folder.name
        appViews.forEach { $0.removeFromSuperview() }
        appViews = store.apps(in: folder).map { app in
            let view = FolderOverlayTileView(app: app, store: store)
            view.onOpen = { [weak self] app in self?.onLaunch?(app) }
            view.onRemove = { [weak self] app in
                guard let self else { return }
                self.store.removeApp(app.id, from: self.folder.id)
            }
            view.onToggleHidden = { [weak self] app in
                guard let self else { return }
                self.store.setHidden(!self.store.isAppHidden(app.id), for: app.id)
            }
            documentView.addSubview(view)
            return view
        }
        emptyStateLabel.isHidden = !appViews.isEmpty
        needsLayout = true
    }

    private func layoutApps() {
        let columns = 4
        let tileWidth: CGFloat = 136
        let tileHeight: CGFloat = 132
        let gap: CGFloat = 10
        let contentWidth = scrollView.contentSize.width
        let gridWidth = CGFloat(columns) * tileWidth + CGFloat(columns - 1) * gap
        let leading = max(0, floor((contentWidth - gridWidth) / 2))

        for (index, view) in appViews.enumerated() {
            let row = index / columns
            let column = index % columns
            view.frame = NSRect(
                x: leading + CGFloat(column) * (tileWidth + gap),
                y: CGFloat(row) * (tileHeight + 10),
                width: tileWidth,
                height: tileHeight
            )
        }
        let rows = max(1, Int(ceil(Double(appViews.count) / Double(columns))))
        documentView.frame = NSRect(
            x: 0,
            y: 0,
            width: contentWidth,
            height: CGFloat(rows) * (tileHeight + 10)
        )
    }

    @objc private func closeOverlay() {
        onClose?()
    }

    @objc private func renameFolder() {
        onRename?(folder)
    }
}
