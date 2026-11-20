import AppKit
import CryptoKit
import Foundation

/// Latest phpMyAdmin release, from https://www.phpmyadmin.net/home_page/version.json
struct PhpMyAdminRelease: Equatable {
    let version: String
    /// Supported PHP range, e.g. `>=7.2,<8.4`.
    let phpConstraint: String?
}

/// Built-in phpMyAdmin: PureValet downloads the official release (SHA-256 checked), writes a config
/// for the local MariaDB socket, and serves it as `phpmyadmin.<tld>` through Valet.
/// Login: macOS user name + empty password (MariaDB `unix_socket` auth), so no password is stored.
enum PhpMyAdmin {
    static let siteName = "phpmyadmin"
    static let mariadbSocket = "/tmp/mysql.sock"
    private static let versionFeed = URL(string: "https://www.phpmyadmin.net/home_page/version.json")!
    private static let versionMarker = ".purevalet-version"

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PureValet/phpMyAdmin", isDirectory: true)
    }

    static var installedVersion: String? {
        (try? String(contentsOf: directory.appendingPathComponent(versionMarker), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fetchLatest() async -> PhpMyAdminRelease? {
        var request = URLRequest(url: versionFeed, timeoutInterval: 15)
        request.setValue("PureValet", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, _) = try? await session.data(for: request) else { return nil }
        return parseRelease(data)
    }

    /// Reads the newest 5.x+ release (the feed also lists the legacy 4.9 branch).
    nonisolated static func parseRelease(_ data: Data) -> PhpMyAdminRelease? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String else { return nil }
        let releases = json["releases"] as? [[String: Any]] ?? []
        let match = releases.first { ($0["version"] as? String) == version }
        return PhpMyAdminRelease(version: version, phpConstraint: match?["php_versions"] as? String)
    }

    /// When the global PHP is outside phpMyAdmin's supported range (e.g. `<8.4`), returns the newest
    /// installed formula that fits, so the site can be isolated on it. Nil means the global PHP is fine
    /// (or nothing better is installed).
    nonisolated static func compatiblePHP(constraint: String?, installed: [PHPFormula], global: String?) -> String? {
        guard let constraint,
              let upper = constraint.split(separator: ",")
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { $0.hasPrefix("<") && !$0.hasPrefix("<=") })?
                .dropFirst() else { return nil }
        let limit = String(upper)
        func fits(_ version: String) -> Bool { Updater.isVersion(limit, newerThan: version) }
        if let global, let current = installed.first(where: { $0.formula == global }), fits(current.version) {
            return nil
        }
        return installed.first { fits($0.version) }?.formula
    }

    /// Downloads, verifies and unpacks the release into `directory`, then writes its config.
    static func install(_ release: PhpMyAdminRelease) async throws {
        let name = "phpMyAdmin-\(release.version)-all-languages"
        let base = "https://files.phpmyadmin.net/phpMyAdmin/\(release.version)/\(name).zip"
        guard let zipURL = URL(string: base), let shaURL = URL(string: base + ".sha256") else {
            throw InstallError.download
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        let (shaData, _) = try await session.data(from: shaURL)
        guard let expected = String(decoding: shaData, as: UTF8.self).split(separator: " ").first.map(String.init),
              expected.count == 64 else { throw InstallError.checksum }

        let (downloaded, response) = try await session.download(from: zipURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw InstallError.download }
        let actual = SHA256.hash(data: try Data(contentsOf: downloaded)).map { String(format: "%02x", $0) }.joined()
        guard actual == expected.lowercased() else { throw InstallError.checksum }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("purevalet-pma-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let unzip = await Shell.run("/usr/bin/ditto", ["-x", "-k", downloaded.path, work.path])
        guard unzip.succeeded else { throw InstallError.unpack }
        let unpacked = work.appendingPathComponent(name)
        guard fm.fileExists(atPath: unpacked.appendingPathComponent("index.php").path) else { throw InstallError.unpack }

        try fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: directory.path) {
            try fm.removeItem(at: directory)
        }
        try fm.moveItem(at: unpacked, to: directory)
        try fm.createDirectory(at: directory.appendingPathComponent("tmp"), withIntermediateDirectories: true)
        try config().write(to: directory.appendingPathComponent("config.inc.php"), atomically: true, encoding: .utf8)
        try release.version.write(to: directory.appendingPathComponent(versionMarker), atomically: true, encoding: .utf8)
    }

    /// Cookie login against the local MariaDB socket; random blowfish secret.
    static func config() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let secret = bytes.map { String(format: "%02x", $0) }.joined()
        return """
        <?php
        // Generated by PureValet. Log in with your macOS user name and an empty password:
        // MariaDB recognises your account through its local socket (unix_socket), so no password is stored.
        declare(strict_types=1);

        $cfg['blowfish_secret'] = sodium_hex2bin('\(secret)');

        $i = 1;
        $cfg['Servers'][$i]['auth_type'] = 'cookie';
        $cfg['Servers'][$i]['host'] = 'localhost';
        $cfg['Servers'][$i]['socket'] = '\(mariadbSocket)';
        $cfg['Servers'][$i]['AllowNoPassword'] = true;
        $cfg['Servers'][$i]['compress'] = false;

        $cfg['TempDir'] = __DIR__ . '/tmp';
        $cfg['UploadDir'] = '';
        $cfg['SaveDir'] = '';
        $cfg['VersionCheck'] = false;

        """
    }

    enum InstallError: LocalizedError {
        case download, checksum, unpack

        var errorDescription: String? {
            switch self {
            case .download: return String(localized: "The phpMyAdmin download failed.")
            case .checksum: return String(localized: "The downloaded phpMyAdmin archive does not match its official SHA-256 checksum.")
            case .unpack: return String(localized: "The phpMyAdmin archive could not be unpacked.")
            }
        }
    }
}
