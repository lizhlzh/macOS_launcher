import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.png"
let outputURL = URL(fileURLWithPath: outputPath)
let size = 1024
let canvas = NSRect(x: 0, y: 0, width: size, height: size)
let iconRect = NSRect(x: 64, y: 64, width: 896, height: 896)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawRoundedRect(
    _ rect: NSRect,
    radius: CGFloat,
    gradient: NSGradient,
    angle: CGFloat,
    stroke: NSColor? = nil,
    strokeWidth: CGFloat = 1
) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    gradient.draw(in: path, angle: angle)
    if let stroke {
        stroke.setStroke()
        path.lineWidth = strokeWidth
        path.stroke()
    }
}

func drawRadialGlow(center: NSPoint, radius: CGFloat, color: NSColor) {
    let path = NSBezierPath(ovalIn: NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    ))
    let gradient = NSGradient(colors: [
        color.withAlphaComponent(0.68),
        color.withAlphaComponent(0.18),
        color.withAlphaComponent(0)
    ])!
    gradient.draw(in: path, relativeCenterPosition: .zero)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to create bitmap context")
}

bitmap.size = NSSize(width: size, height: size)

let previousContext = NSGraphicsContext.current
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSColor.clear.setFill()
canvas.fill()

let basePath = NSBezierPath(roundedRect: iconRect, xRadius: 214, yRadius: 214)
NSGraphicsContext.saveGraphicsState()
let baseShadow = NSShadow()
baseShadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
baseShadow.shadowOffset = NSSize(width: 0, height: -28)
baseShadow.shadowBlurRadius = 48
baseShadow.set()
NSGradient(colors: [
    color(32, 42, 96),
    color(53, 96, 179),
    color(52, 194, 218)
])!.draw(in: basePath, angle: -38)
NSGraphicsContext.restoreGraphicsState()

basePath.addClip()
drawRadialGlow(center: NSPoint(x: 248, y: 826), radius: 390, color: color(180, 220, 255))
drawRadialGlow(center: NSPoint(x: 780, y: 254), radius: 430, color: color(51, 255, 220))
drawRadialGlow(center: NSPoint(x: 756, y: 816), radius: 320, color: color(178, 114, 255))

let topSheen = NSBezierPath(roundedRect: NSRect(x: 96, y: 560, width: 832, height: 380), xRadius: 178, yRadius: 178)
NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.40),
    NSColor.white.withAlphaComponent(0.06),
    NSColor.white.withAlphaComponent(0)
])!.draw(in: topSheen, angle: 90)

let panelRect = NSRect(x: 218, y: 226, width: 588, height: 588)
NSGraphicsContext.saveGraphicsState()
let panelShadow = NSShadow()
panelShadow.shadowColor = NSColor.black.withAlphaComponent(0.26)
panelShadow.shadowOffset = NSSize(width: 0, height: -18)
panelShadow.shadowBlurRadius = 34
panelShadow.set()
drawRoundedRect(
    panelRect,
    radius: 128,
    gradient: NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.38),
        NSColor.white.withAlphaComponent(0.16),
        color(86, 218, 255, 0.20)
    ])!,
    angle: 130,
    stroke: NSColor.white.withAlphaComponent(0.34),
    strokeWidth: 2
)
NSGraphicsContext.restoreGraphicsState()

let gridOrigin = NSPoint(x: 310, y: 318)
let cellSize: CGFloat = 128
let gap: CGFloat = 30

for row in 0..<3 {
    for column in 0..<3 {
        let x = gridOrigin.x + CGFloat(column) * (cellSize + gap)
        let y = gridOrigin.y + CGFloat(2 - row) * (cellSize + gap)
        let rect = NSRect(x: x, y: y, width: cellSize, height: cellSize)
        let isCenter = row == 1 && column == 1
        let isCorner = (row == 0 || row == 2) && (column == 0 || column == 2)

        NSGraphicsContext.saveGraphicsState()
        let cellShadow = NSShadow()
        cellShadow.shadowColor = NSColor.black.withAlphaComponent(isCenter ? 0.24 : 0.16)
        cellShadow.shadowOffset = NSSize(width: 0, height: -8)
        cellShadow.shadowBlurRadius = isCenter ? 18 : 12
        cellShadow.set()

        let gradient: NSGradient
        if isCenter {
            gradient = NSGradient(colors: [
                color(248, 255, 255, 0.94),
                color(86, 237, 255, 0.82),
                color(71, 128, 255, 0.74)
            ])!
        } else if isCorner {
            gradient = NSGradient(colors: [
                NSColor.white.withAlphaComponent(0.72),
                color(176, 226, 255, 0.48),
                color(97, 137, 255, 0.28)
            ])!
        } else {
            gradient = NSGradient(colors: [
                NSColor.white.withAlphaComponent(0.62),
                color(182, 244, 255, 0.40),
                color(123, 148, 255, 0.24)
            ])!
        }

        drawRoundedRect(
            rect,
            radius: 34,
            gradient: gradient,
            angle: 115,
            stroke: NSColor.white.withAlphaComponent(isCenter ? 0.60 : 0.34),
            strokeWidth: isCenter ? 2.5 : 1.5
        )
        NSGraphicsContext.restoreGraphicsState()

        let highlightRect = NSRect(
            x: rect.minX + 16,
            y: rect.maxY - 34,
            width: rect.width - 32,
            height: 18
        )
        NSColor.white.withAlphaComponent(isCenter ? 0.42 : 0.28).setFill()
        NSBezierPath(roundedRect: highlightRect, xRadius: 9, yRadius: 9).fill()
    }
}

let rimPath = NSBezierPath(roundedRect: iconRect.insetBy(dx: 1.5, dy: 1.5), xRadius: 214, yRadius: 214)
NSColor.white.withAlphaComponent(0.32).setStroke()
rimPath.lineWidth = 3
rimPath.stroke()

let lowerRimPath = NSBezierPath(roundedRect: iconRect.insetBy(dx: 18, dy: 18), xRadius: 196, yRadius: 196)
NSColor.black.withAlphaComponent(0.12).setStroke()
lowerRimPath.lineWidth = 2
lowerRimPath.stroke()

NSGraphicsContext.current = previousContext

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to render icon PNG")
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL, options: .atomic)
print(outputURL.path)
