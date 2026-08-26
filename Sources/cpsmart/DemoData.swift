#if DEBUG
import AppKit

/// 开发用演示数据：配合 `--demo-data` 启动参数弹出含示例内容的浮窗，
/// 不读写真实历史文件，便于截图审查 UI。仅 DEBUG 编译包含。
enum DemoData {
    static func makeEntries() -> [ClipboardEntry] {
        let now = Date()
        return [
            ClipboardEntry(
                payload: .text("git rebase -i HEAD~3"),
                createdAt: now.addingTimeInterval(-40),
                sourceAppName: "终端",
                sourceAppBundleID: "com.apple.Terminal",
                isPinned: true
            ),
            ClipboardEntry(
                payload: .image(
                    data: gradientImage(
                        colors: [
                            NSColor(srgbRed: 0.42, green: 0.36, blue: 0.91, alpha: 1),
                            NSColor(srgbRed: 0.12, green: 0.53, blue: 0.90, alpha: 1)
                        ],
                        size: NSSize(width: 1600, height: 1000),
                        seed: 1
                    ),
                    pasteboardType: NSPasteboard.PasteboardType.png.rawValue
                ),
                createdAt: now.addingTimeInterval(-5 * 60),
                sourceAppName: "Safari",
                sourceAppBundleID: "com.apple.Safari"
            ),
            ClipboardEntry(
                payload: .text("""
                    func applicationDidFinishLaunching(_ notification: Notification) {
                        NSApp.setActivationPolicy(.accessory)
                        configureHistoryWindow()
                        configureStatusItem()
                    }
                    """),
                createdAt: now.addingTimeInterval(-12 * 60),
                sourceAppName: "Xcode",
                sourceAppBundleID: "com.apple.dt.Xcode"
            ),
            ClipboardEntry(
                payload: .text("https://github.com/dongdaoguang/cpsmart"),
                createdAt: now.addingTimeInterval(-26 * 60),
                sourceAppName: "Safari",
                sourceAppBundleID: "com.apple.Safari"
            ),
            ClipboardEntry(
                payload: .image(
                    data: gradientImage(
                        colors: [
                            NSColor(srgbRed: 0.98, green: 0.42, blue: 0.52, alpha: 1),
                            NSColor(srgbRed: 0.98, green: 0.75, blue: 0.30, alpha: 1)
                        ],
                        size: NSSize(width: 900, height: 900),
                        seed: 2
                    ),
                    pasteboardType: NSPasteboard.PasteboardType.png.rawValue
                ),
                createdAt: now.addingTimeInterval(-48 * 60),
                sourceAppName: "预览",
                sourceAppBundleID: "com.apple.Preview"
            ),
            ClipboardEntry(
                payload: .text("剪贴板历史可能包含隐私信息。cpsmart 不联网、不上传历史，并会跳过带标准敏感标记的内容。"),
                createdAt: now.addingTimeInterval(-72 * 60),
                sourceAppName: "备忘录",
                sourceAppBundleID: "com.apple.Notes"
            ),
            ClipboardEntry(
                payload: .files(["/Applications/Safari.app"]),
                createdAt: now.addingTimeInterval(-2 * 3600),
                sourceAppName: "访达",
                sourceAppBundleID: "com.apple.finder"
            ),
            ClipboardEntry(
                payload: .text("""
                    - [x] 搜索过滤
                    - [x] 图片缩略图
                    - [x] 来源应用图标
                    - [x] 自适应预览
                    """),
                createdAt: now.addingTimeInterval(-3 * 3600),
                sourceAppName: "备忘录",
                sourceAppBundleID: "com.apple.Notes"
            ),
            ClipboardEntry(
                payload: .files([
                    "/System/Applications/Mail.app",
                    "/System/Applications/Calendar.app",
                    "/System/Applications/Notes.app"
                ]),
                createdAt: now.addingTimeInterval(-5 * 3600),
                sourceAppName: "访达",
                sourceAppBundleID: "com.apple.finder"
            )
        ]
    }

    static func makePinboards() -> [Pinboard] {
        [
            Pinboard(
                name: "常用命令",
                color: .red,
                entries: [
                    ClipboardEntry(payload: .text("git status --short --branch")),
                    ClipboardEntry(payload: .text("swift build && bash Scripts/run_tests.sh")),
                    ClipboardEntry(payload: .text("curl -fsSL https://example.com/install.sh | sh"))
                ]
            ),
            Pinboard(
                name: "常用回复",
                color: .blue,
                entries: [
                    ClipboardEntry(payload: .text("收到，我确认后尽快回复你。")),
                    ClipboardEntry(payload: .text("麻烦补充一下复现步骤和系统版本，谢谢。"))
                ]
            )
        ]
    }

    private static func gradientImage(colors: [NSColor], size: NSSize, seed: Int) -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: colors)?.draw(
            in: NSRect(origin: .zero, size: size),
            angle: seed == 1 ? 30 : 135
        )
        // 画几个半透明几何块，让缩略图有可辨识的内容。
        NSColor.white.withAlphaComponent(0.22).setFill()
        let circleRect = NSRect(
            x: size.width * 0.12,
            y: size.height * 0.18,
            width: size.width * 0.30,
            height: size.width * 0.30
        )
        NSBezierPath(ovalIn: circleRect).fill()
        NSColor.black.withAlphaComponent(0.18).setFill()
        let barRect = NSRect(
            x: size.width * 0.52,
            y: size.height * 0.55,
            width: size.width * 0.36,
            height: size.height * 0.14
        )
        NSBezierPath(roundedRect: barRect, xRadius: 12, yRadius: 12).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return Data()
        }
        return png
    }
}
#endif
