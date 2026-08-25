import AppKit

/// 轻量预览的内容尺寸策略。
///
/// 返回值是 NSPopover 的 contentSize，不包含系统绘制的箭头和阴影。
/// 所有上限都基于承载卡片所在屏幕的 visibleFrame，不能假定屏幕原点为零。
enum AdaptivePreviewSizing {
    struct Limits {
        let maximumWidth: CGFloat
        let maximumHeight: CGFloat
    }

    private static let textHorizontalPadding: CGFloat = 32
    private static let textChromeHeight: CGFloat = 70
    private static let imageHorizontalPadding: CGFloat = 24
    private static let imageChromeHeight: CGFloat = 72

    static func limits(visibleFrame: NSRect, sourceFrame: NSRect) -> Limits {
        // 宽度上限兼顾大屏信息密度和小屏安全边距。
        let screenWidthCap = max(240, visibleFrame.width - 48)
        let maximumWidth = min(720, screenWidthCap)

        // 历史浮窗位于屏幕底部，优先使用卡片上方空间。NSPopover 在空间不足时
        // 仍可自动翻转；这里同时用整屏比例兜底，避免异常窗口位置算出负尺寸。
        let spaceAboveCard = visibleFrame.maxY - sourceFrame.maxY - 20
        let screenHeightCap = max(180, visibleFrame.height - 48)
        let preferredHeightCap = min(560, visibleFrame.height * 0.66)
        let maximumHeight = min(
            screenHeightCap,
            max(180, min(preferredHeightCap, spaceAboveCard))
        )

        return Limits(maximumWidth: maximumWidth, maximumHeight: maximumHeight)
    }

    static func textSize(
        for text: String,
        font: NSFont,
        visibleFrame: NSRect,
        sourceFrame: NSRect
    ) -> NSSize {
        let limits = limits(visibleFrame: visibleFrame, sourceFrame: sourceFrame)
        let minimumWidth = min(320, limits.maximumWidth)
        let minimumHeight = min(150, limits.maximumHeight)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]
        let longestLineWidth = lines
            .map { NSAttributedString(string: String($0), attributes: attributes).size().width }
            .max() ?? 0

        // 短内容先尝试紧凑布局。最终高度使用真实排版结果，而不是字符数估算。
        let compactMaximumWidth = min(480, limits.maximumWidth)
        let compactWidth = clamp(
            ceil(longestLineWidth) + textHorizontalPadding,
            minimum: minimumWidth,
            maximum: compactMaximumWidth
        )
        let compactHeight = measuredTextHeight(text, font: font, width: compactWidth)
            + textChromeHeight
        if text.count <= 600,
           lines.count <= 10,
           compactHeight <= min(240, limits.maximumHeight) {
            return NSSize(
                width: compactWidth,
                height: clamp(
                    ceil(compactHeight),
                    minimum: minimumHeight,
                    maximum: limits.maximumHeight
                )
            )
        }

        // 中等内容使用稳定的阅读宽度；只有真正放不下时才进入大型滚动布局。
        let standardWidth = min(560, limits.maximumWidth)
        let standardHeight = measuredTextHeight(text, font: font, width: standardWidth)
            + textChromeHeight
        if standardHeight <= min(420, limits.maximumHeight) {
            return NSSize(
                width: max(minimumWidth, standardWidth),
                height: clamp(
                    ceil(standardHeight),
                    minimum: min(240, limits.maximumHeight),
                    maximum: limits.maximumHeight
                )
            )
        }

        return NSSize(
            width: max(minimumWidth, min(680, limits.maximumWidth)),
            height: limits.maximumHeight
        )
    }

    static func imageSize(
        pixelSize: NSSize,
        visibleFrame: NSRect,
        sourceFrame: NSRect
    ) -> NSSize {
        let limits = limits(visibleFrame: visibleFrame, sourceFrame: sourceFrame)
        let minimumWidth = min(260, limits.maximumWidth)
        let minimumHeight = min(170, limits.maximumHeight)
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            return NSSize(width: minimumWidth, height: minimumHeight)
        }

        let maximumImageWidth = max(1, limits.maximumWidth - imageHorizontalPadding)
        let maximumImageHeight = max(1, limits.maximumHeight - imageChromeHeight)
        // scale 永不超过 1：小图片不放大，大图片才等比缩小。
        let scale = min(
            1,
            maximumImageWidth / pixelSize.width,
            maximumImageHeight / pixelSize.height
        )
        let displayedSize = NSSize(
            width: floor(pixelSize.width * scale),
            height: floor(pixelSize.height * scale)
        )

        return NSSize(
            width: clamp(
                displayedSize.width + imageHorizontalPadding,
                minimum: minimumWidth,
                maximum: limits.maximumWidth
            ),
            height: clamp(
                displayedSize.height + imageChromeHeight,
                minimum: minimumHeight,
                maximum: limits.maximumHeight
            )
        )
    }

    static func centeredQuickLookFrame(
        panelSize: NSSize,
        visibleFrame: NSRect,
        margin: CGFloat = 24
    ) -> NSRect {
        let safeFrame = visibleFrame.insetBy(dx: margin, dy: margin)
        let constrainedSize = NSSize(
            width: min(panelSize.width, safeFrame.width),
            height: min(panelSize.height, safeFrame.height)
        )
        return NSRect(
            x: safeFrame.midX - constrainedSize.width / 2,
            y: safeFrame.midY - constrainedSize.height / 2,
            width: constrainedSize.width,
            height: constrainedSize.height
        )
    }

    private static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 1.5
        return style
    }

    private static func measuredTextHeight(
        _ text: String,
        font: NSFont,
        width: CGFloat
    ) -> CGFloat {
        let contentWidth = max(1, width - textHorizontalPadding)
        let attributed = NSAttributedString(
            string: text.isEmpty ? " " : text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        return attributed.boundingRect(
            with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height
    }

    private static func clamp(
        _ value: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        min(max(value, min(minimum, maximum)), maximum)
    }
}
