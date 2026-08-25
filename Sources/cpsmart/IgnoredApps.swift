import Foundation

final class IgnoredApps {
    static let defaultsKey = "ignoredBundleIDs"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var bundleIDs: [String] {
        get {
            userDefaults.stringArray(forKey: Self.defaultsKey) ?? []
        }
        set {
            let normalized = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { result, bundleID in
                    guard !result.contains(where: {
                        $0.caseInsensitiveCompare(bundleID) == .orderedSame
                    }) else { return }
                    result.append(bundleID)
                }
            userDefaults.set(normalized, forKey: Self.defaultsKey)
        }
    }

    func contains(_ bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return bundleIDs.contains {
            $0.caseInsensitiveCompare(bundleID) == .orderedSame
        }
    }

    func add(_ bundleID: String) {
        bundleIDs.append(bundleID)
    }

    func remove(_ bundleID: String) {
        bundleIDs.removeAll {
            $0.caseInsensitiveCompare(bundleID) == .orderedSame
        }
    }
}
