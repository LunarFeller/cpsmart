import AppKit
import Foundation

struct AppVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" {
            value.removeFirst()
        }

        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts.allSatisfy({ Int($0) != nil }) else {
            return nil
        }

        var normalized = parts.compactMap { Int($0) }
        while normalized.count > 1 && normalized.last == 0 {
            normalized.removeLast()
        }
        components = normalized
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

struct GitHubReleaseAsset: Equatable {
    let name: String
    let browserDownloadURL: URL
}

struct GitHubRelease {
    let tagName: String
    let htmlURL: URL

    init?(latestReleaseURL: URL) {
        guard UpdateSupport.isTrustedReleasePageURL(latestReleaseURL) else { return nil }
        let tagName = latestReleaseURL.lastPathComponent
        guard AppVersion(tagName) != nil else { return nil }
        self.tagName = tagName
        htmlURL = latestReleaseURL
    }

    var version: AppVersion? {
        AppVersion(tagName)
    }

    var installerAsset: GitHubReleaseAsset? {
        var versionString = tagName
        if versionString.first == "v" || versionString.first == "V" {
            versionString.removeFirst()
        }
        let fileName = "cpsmart-\(versionString)-universal.dmg"
        guard let downloadURL = URL(
            string: "https://github.com/dongdaoguang/cpsmart/releases/download/\(tagName)/\(fileName)"
        ) else {
            return nil
        }
        return GitHubReleaseAsset(name: fileName, browserDownloadURL: downloadURL)
    }
}

enum UpdateSupport {
    static func installationInstructions(installerOpened: Bool) -> String {
        let location = installerOpened
            ? "安装镜像已经打开。"
            : "安装包已保存到“下载”文件夹，请先打开它。"
        return """
        \(location)

        接下来只需：
        1. 点击下方“退出 cpsmart”。
        2. 把镜像中的新版拖到“应用程序”，选择“替换”。
        3. 重新打开 cpsmart。

        如果更新后自动粘贴失效，再尝试粘贴一次并选择权限修复。cpsmart 会清理旧记录、打开正确页面并自动退出；然后点击“+”添加 /Applications/cpsmart.app、开启开关并重新启动。
        """
    }

    static func isTrustedReleasePageURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com" else {
            return false
        }
        let prefix = "/dongdaoguang/cpsmart/releases/tag/"
        guard url.path.hasPrefix(prefix) else { return false }
        let tag = url.path.dropFirst(prefix.count)
        return !tag.isEmpty && !tag.contains("/")
    }

    static func isTrustedReleaseDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com" else {
            return false
        }
        return url.path.hasPrefix("/dongdaoguang/cpsmart/releases/download/")
    }

    static func centeredWindowFrame(windowSize: NSSize, visibleFrame: NSRect) -> NSRect {
        let origin = NSPoint(
            x: min(
                max(visibleFrame.midX - windowSize.width / 2, visibleFrame.minX),
                visibleFrame.maxX - windowSize.width
            ),
            y: min(
                max(visibleFrame.midY - windowSize.height / 2, visibleFrame.minY),
                visibleFrame.maxY - windowSize.height
            )
        )
        return NSRect(origin: origin, size: windowSize)
    }
}
