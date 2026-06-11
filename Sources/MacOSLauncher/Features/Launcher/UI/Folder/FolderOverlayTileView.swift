import AppKit

/// A compact application tile used only inside the folder overlay.
@MainActor
final class FolderOverlayTileView: NSView {
    var onOpen: ((LauncherAppInfo) -> Void)?
    var onRemove: ((LauncherAppInfo) -> Void)?
    var onToggleHidden: ((LauncherAppInfo) -> Void)?

    private let app: LauncherAppInfo
    private let store: LauncherStore
    private let iconButton = NSButton()
    private let label = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    init(app: LauncherAppInfo, store: LauncherStore) {
        self.app = app
        self.store = store
        super.init(frame: .zero)

        iconButton.isBordered = false
        iconButton.image = store.appIcon(for: app, size: 82)
        iconButton.imageScaling = .scaleProportionallyUpOrDown
        iconButton.target = self
        iconButton.action = #selector(openApp)
        addSubview(iconButton)

        label.stringValue = app.title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        iconButton.frame = NSRect(
            x: floor((bounds.width - 82) / 2),
            y: 4,
            width: 82,
            height: 82
        )
        label.frame = NSRect(x: 2, y: 94, width: bounds.width - 4, height: 34)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let visibilityTitle = store.isAppHidden(app.id) ? "Unhide App" : "Hide App"
        menu.addItem(ClosureMenuItem(title: visibilityTitle) { [weak self] in
            guard let self else { return }
            self.onToggleHidden?(self.app)
        })
        menu.addItem(ClosureMenuItem(title: "Remove from Folder") { [weak self] in
            guard let self else { return }
            self.onRemove?(self.app)
        })
        return menu
    }

    @objc private func openApp() {
        onOpen?(app)
    }
}
