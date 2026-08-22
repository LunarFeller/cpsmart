import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate_icon.swift OUTPUT_ICONSET\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func makeIcon(size: Int) throws -> Data {
    let canvas = CGFloat(size)
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
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "ClipShelfIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }

    let context = graphicsContext.cgContext
    context.setShouldAntialias(true)
    context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

    let inset = canvas * 0.05
    let backgroundRect = NSRect(
        x: inset,
        y: inset,
        width: canvas - inset * 2,
        height: canvas - inset * 2
    )
    let background = NSBezierPath(
        roundedRect: backgroundRect,
        xRadius: canvas * 0.22,
        yRadius: canvas * 0.22
    )
    background.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.18, green: 0.39, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.46, green: 0.20, blue: 0.91, alpha: 1)
    ])!
    gradient.draw(in: background, angle: -55)

    func drawSheet(offsetX: CGFloat, offsetY: CGFloat, alpha: CGFloat) {
        let rect = NSRect(
            x: canvas * (0.25 + offsetX),
            y: canvas * (0.22 + offsetY),
            width: canvas * 0.50,
            height: canvas * 0.58
        )
        let sheet = NSBezierPath(
            roundedRect: rect,
            xRadius: canvas * 0.055,
            yRadius: canvas * 0.055
        )
        NSColor.white.withAlphaComponent(alpha).setFill()
        sheet.fill()
    }

    drawSheet(offsetX: -0.055, offsetY: 0.06, alpha: 0.38)
    drawSheet(offsetX: 0, offsetY: 0, alpha: 0.96)

    NSColor(calibratedRed: 0.28, green: 0.28, blue: 0.45, alpha: 0.65).setFill()
    for index in 0..<3 {
        let bar = NSBezierPath(
            roundedRect: NSRect(
                x: canvas * 0.33,
                y: canvas * (0.35 + CGFloat(index) * 0.115),
                width: canvas * (index == 0 ? 0.25 : 0.34),
                height: max(canvas * 0.045, 1)
            ),
            xRadius: canvas * 0.022,
            yRadius: canvas * 0.022
        )
        bar.fill()
    }

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ClipShelfIcon", code: 2)
    }
    return png
}

for (name, size) in outputs {
    let data = try makeIcon(size: size)
    try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
}
