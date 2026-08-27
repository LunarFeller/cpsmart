import AppKit

enum DisplayGeometry {
    static func screenIndex(containing point: NSPoint, frames: [NSRect]) -> Int? {
        frames.firstIndex { NSMouseInRect(point, $0, false) }
    }

    static func historyFrame(visibleFrame: NSRect, height: CGFloat) -> NSRect {
        NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: height
        )
    }
}
