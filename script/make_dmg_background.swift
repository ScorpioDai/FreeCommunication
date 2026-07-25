#!/usr/bin/env swift

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("usage: make_dmg_background.swift <output.png>\n", stderr)
    exit(2)
}

let width = 720
let height = 430
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("failed to create image buffer\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("failed to create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = context

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
NSColor(calibratedRed: 0.965, green: 0.973, blue: 0.982, alpha: 1).setFill()
canvas.fill()

let header = NSRect(x: 0, y: height - 8, width: width, height: 8)
NSColor(calibratedRed: 0.10, green: 0.48, blue: 0.92, alpha: 1).setFill()
header.fill()

let centered = NSMutableParagraphStyle()
centered.alignment = .center

func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: centered
    ]
    text.draw(
        in: NSRect(x: 30, y: y, width: CGFloat(width - 60), height: font.pointSize * 1.5),
        withAttributes: attributes
    )
}

drawCentered(
    "FreeCommunication",
    y: 350,
    font: .systemFont(ofSize: 31, weight: .semibold),
    color: NSColor(calibratedWhite: 0.10, alpha: 1)
)
drawCentered(
    "拖到“应用程序”完成安装",
    y: 311,
    font: .systemFont(ofSize: 17, weight: .medium),
    color: NSColor(calibratedWhite: 0.25, alpha: 1)
)
drawCentered(
    "Drag FreeCommunication to Applications",
    y: 282,
    font: .systemFont(ofSize: 14, weight: .regular),
    color: NSColor(calibratedWhite: 0.43, alpha: 1)
)

let arrow = NSBezierPath()
arrow.lineWidth = 7
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 292, y: 190))
arrow.line(to: NSPoint(x: 421, y: 190))
arrow.move(to: NSPoint(x: 397, y: 214))
arrow.line(to: NSPoint(x: 421, y: 190))
arrow.line(to: NSPoint(x: 397, y: 166))
NSColor(calibratedRed: 0.13, green: 0.51, blue: 0.89, alpha: 1).setStroke()
arrow.stroke()

drawCentered(
    "安装后可从“应用程序”或启动台打开",
    y: 42,
    font: .systemFont(ofSize: 13, weight: .regular),
    color: NSColor(calibratedWhite: 0.48, alpha: 1)
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to encode PNG\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
} catch {
    fputs("failed to write background: \(error)\n", stderr)
    exit(1)
}
