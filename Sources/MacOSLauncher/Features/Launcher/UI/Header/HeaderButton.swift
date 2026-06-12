import AppKit
import QuartzCore

/// A native target/action control with explicit hover and pressed rendering.
final class HeaderButton: NSControl {
    private var trackingAreaToken: NSTrackingArea?
    private var hovering = false
    private var pressed = false
    private let hoverShape = CAShapeLayer()
    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    var debugName = "unknown"

    var image: NSImage? {
        didSet {
            symbolView.image = image
            needsLayout = true
        }
    }

    var title = "" {
        didSet {
            titleLabel.stringValue = title
            needsLayout = true
        }
    }

    var textFont: NSFont = .systemFont(ofSize: 13.5, weight: .semibold) {
        didSet {
            titleLabel.font = textFont
            needsLayout = true
        }
    }

    var contentTintColor: NSColor = .white {
        didSet {
            updateForegroundColor()
        }
    }

    override var isEnabled: Bool {
        didSet {
            updateForegroundColor()
            updateBackground(animated: false)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureHoverShape()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureHoverShape() {
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        hoverShape.fillColor = NSColor.white.withAlphaComponent(0.018).cgColor
        hoverShape.strokeColor = NSColor.clear.cgColor
        hoverShape.lineWidth = 1
        layer?.insertSublayer(hoverShape, at: 0)

        symbolView.imageScaling = .scaleProportionallyDown
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 15,
            weight: .semibold
        )
        addSubview(symbolView)

        titleLabel.font = textFont
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)
        updateForegroundColor()
    }

    override func layout() {
        super.layout()
        hoverShape.frame = bounds
        let hoverRect = bounds.insetBy(dx: 1.5, dy: 3)
        hoverShape.path = CGPath(
            roundedRect: hoverRect,
            cornerWidth: hoverRect.height / 2,
            cornerHeight: hoverRect.height / 2,
            transform: nil
        )

        let iconSize: CGFloat = image == nil ? 0 : 18
        let spacing: CGFloat = image == nil || title.isEmpty ? 0 : 10
        let measuredTitleWidth = title.isEmpty
            ? CGFloat.zero
            : ceil((title as NSString).size(withAttributes: [.font: textFont]).width)
        let maxTitleWidth = max(0, bounds.width - iconSize - spacing - 14)
        let titleWidth = min(measuredTitleWidth, maxTitleWidth)
        let groupWidth = iconSize + spacing + titleWidth
        let startX = max(8, floor((bounds.width - groupWidth) / 2))
        let centerY = bounds.midY

        symbolView.isHidden = image == nil
        titleLabel.isHidden = title.isEmpty
        if image != nil {
            symbolView.frame = NSRect(
                x: startX,
                y: floor(centerY - iconSize / 2),
                width: iconSize,
                height: iconSize
            )
        }
        titleLabel.frame = NSRect(
            x: startX + iconSize + spacing,
            y: floor(centerY - 10),
            width: titleWidth,
            height: 20
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaToken {
            removeTrackingArea(trackingAreaToken)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(tracking)
        trackingAreaToken = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        updateBackground(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        updateBackground(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        LumaEventLog.shared.writeInteraction(
            .header,
            "header.mouseDown",
            fields: [
                "button": debugName,
                "isEnabled": isEnabled,
                "localPoint": lumaLogPoint(convert(event.locationInWindow, from: nil)),
                "frame": lumaLogRect(frame),
                "windowIsKey": window?.isKeyWindow ?? false,
                "firstResponder": lumaLogOptional(window?.firstResponder)
            ]
        )
        guard isEnabled else {
            LumaEventLog.shared.writeInteraction(
                .header,
                "header.actionSkipped",
                fields: [
                    "button": debugName,
                    "reason": "disabled"
                ]
            )
            return
        }

        pressed = true
        updateBackground(animated: false)

        if let action {
            LumaEventLog.shared.writeInteraction(
                .header,
                "header.sendAction",
                fields: [
                    "button": debugName,
                    "action": NSStringFromSelector(action),
                    "targetType": target.map { String(reflecting: type(of: $0)) } ?? "nil"
                ]
            )
            sendAction(action, to: target)
        } else {
            LumaEventLog.shared.writeInteraction(
                .header,
                "header.actionSkipped",
                fields: [
                    "button": debugName,
                    "reason": "missingAction"
                ]
            )
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pressed = false
            self.updateBackground(animated: true)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func updateForegroundColor() {
        let alpha: CGFloat = isEnabled ? 1 : 0.45
        let color = contentTintColor.withAlphaComponent(
            contentTintColor.alphaComponent * alpha
        )
        symbolView.contentTintColor = color
        titleLabel.textColor = color
    }

    private func updateBackground(animated: Bool) {
        let backgroundColor: NSColor
        let borderColor: NSColor
        if pressed {
            backgroundColor = .white.withAlphaComponent(0.16)
            borderColor = .white.withAlphaComponent(0.20)
        } else if hovering && isEnabled {
            backgroundColor = .white.withAlphaComponent(0.10)
            borderColor = .white.withAlphaComponent(0.14)
        } else {
            backgroundColor = .white.withAlphaComponent(0.018)
            borderColor = .clear
        }

        let background = backgroundColor.cgColor
        let border = borderColor.cgColor
        guard animated else {
            hoverShape.fillColor = background
            hoverShape.strokeColor = border
            return
        }

        let backgroundAnimation = CABasicAnimation(keyPath: "fillColor")
        backgroundAnimation.fromValue = hoverShape.presentation()?.fillColor
            ?? hoverShape.fillColor
        backgroundAnimation.toValue = background
        backgroundAnimation.duration = 0.16
        backgroundAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let borderAnimation = CABasicAnimation(keyPath: "strokeColor")
        borderAnimation.fromValue = hoverShape.presentation()?.strokeColor
            ?? hoverShape.strokeColor
        borderAnimation.toValue = border
        borderAnimation.duration = 0.16
        borderAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)

        hoverShape.fillColor = background
        hoverShape.strokeColor = border
        hoverShape.add(backgroundAnimation, forKey: "hoverBackground")
        hoverShape.add(borderAnimation, forKey: "hoverBorder")
    }
}
