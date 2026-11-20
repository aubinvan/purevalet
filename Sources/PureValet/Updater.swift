import AppKit
import Foundation
import Observation

/// A newer release published on GitHub.
struct AvailableUpdate: Equatable {
    let version: String
    let releaseURL: URL
    let downloadURL: URL?
}

/// Lightweight update check: one request to the GitHub Releases API, at most once a day
/// (at launch or when the menu opens), and on demand. No timer, no dependency,
/// nothing is downloaded or installed automatically.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    nonisolated static let autoCheckKey = "checkForUpdatesAutomatically"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/aubinvan/purevalet/releases/latest")!
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    var available: AvailableUpdate?
    var isChecking = false
    /// Result of the last manual check, shown in the About pane.
    var statusMessage: String?

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Automatic check, skipped if disabled or if the last check is less than a day old.
    func checkIfDue() async {
        guard UserDefaults.standard.bool(forKey: Self.autoCheckKey) else { return }
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < Self.checkInterval { return }
        await check(manual: false)
    }

    func check(manual: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        if manual { statusMessage = nil }

        var request = URLRequest(url: Self.latestReleaseAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PureValet/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let release = Self.parseRelease(data) else {
                throw URLError(.badServerResponse)
            }
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            if Self.isVersion(release.version, newerThan: currentVersion) {
                available = release
                statusMessage = String(localized: "Version \(release.version) is available")
            } else {
                available = nil
                statusMessage = String(localized: "PureValet is up to date")
            }
        } catch {
            if manual { statusMessage = String(localized: "Could not check for updates") }
        }
    }

    func download(_ update: AvailableUpdate) {
        NSWorkspace.shared.open(update.downloadURL ?? update.releaseURL)
    }

    func openReleaseNotes(_ update: AvailableUpdate) {
        NSWorkspace.shared.open(update.releaseURL)
    }

    // MARK: - Parsing (pure, tested)

    /// Reads `tag_name`, `html_url` and the `.dmg` asset from a GitHub release JSON.
    nonisolated static func parseRelease(_ data: Data) -> AvailableUpdate? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets
            .compactMap { $0["browser_download_url"] as? String }
            .first { $0.hasSuffix(".dmg") }
            .flatMap(URL.init(string:))
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return AvailableUpdate(version: version, releaseURL: page, downloadURL: dmg)
    }

    /// Numeric comparison of dotted versions: `0.10.0` is newer than `0.9.2`.
    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
