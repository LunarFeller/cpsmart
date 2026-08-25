import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate_icon.swift OUTPUT_ICONSET\n", stderr)
    exit(2)
}

let scriptDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let projectDirectory = scriptDirectory.deletingLastPathComponent()
let sourceURL = projectDirectory
    .appendingPathComponent("Resources", isDirectory: true)
    .appendingPathComponent("AppIconSource.png")

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Unable to load app icon source at \(sourceURL.path)\n", stderr)
    exit(1)
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
        throw NSError(domain: "cpsmartIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }

    let context = graphicsContext.cgContext
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

    // The generated artwork includes a white preview canvas. Clip it back to the
    // macOS icon tile so Finder and the Dock see transparent corners rather than
    // an opaque white square.
    let tileInset = canvas * 0.075
    let tileRect = CGRect(
        x: tileInset,
        y: tileInset,
        width: canvas - tileInset * 2,
        height: canvas - tileInset * 2
    )
    let tilePath = CGPath(
        roundedRect: tileRect,
        cornerWidth: canvas * 0.205,
        cornerHeight: canvas * 0.205,
        transform: nil
    )

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -canvas * 0.018),
        blur: canvas * 0.025,
        color: NSColor.black.withAlphaComponent(0.24).cgColor
    )
    context.addPath(tilePath)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    sourceImage.draw(
        in: NSRect(x: 0, y: 0, width: canvas, height: canvas),
        from: NSRect(origin: .zero, size: sourceImage.size),
        operation: .copy,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    context.restoreGState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "cpsmartIcon", code: 2)
    }
    return png
}

for (name, size) in outputs {
    let data = try makeIcon(size: size)
    try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
}
