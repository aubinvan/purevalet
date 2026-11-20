import Foundation

/// Reads and writes Laravel Valet's on-disk state directly (`~/.config/valet`), using Valet's own
/// stubs, so the files stay 100 % compatible with the `valet` CLI.
///
/// Why: Valet runs `sudo` even for read-only commands (it resolves Homebrew through `sudo -u`), which
/// fails on a standard (non-admin) account. Reading the files needs no privilege at all, and in
/// rootless mode PureValet also performs the site changes here instead of through `sudo valet …`.
struct ValetFiles {
    static let staticPrefix = "41c270e4-5535-4daa-b23e-c269744c2f45"
    static let isolatedMarker = "# ISOLATED_PHP_VERSION="

    let home: String
    let valetPackage: String

    init(home: String = "\(Shell.home)/.config/valet", valetPackage: String = "\(Shell.home)/.composer/vendor/laravel/valet") {
        self.home = home
        self.valetPackage = valetPackage
    }

    var sitesDir: String { "\(home)/Sites" }
    var nginxDir: String { "\(home)/Nginx" }
    var certificatesDir: String { "\(home)/Certificates" }
    var caDir: String { "\(home)/CA" }
    var caPem: String { "\(caDir)/LaravelValetCASelfSigned.pem" }
    var caKey: String { "\(caDir)/LaravelValetCASelfSigned.key" }
    var serverPath: String { "\(valetPackage)/server.php" }
    var exists: Bool { FileManager.default.fileExists(atPath: "\(home)/config.json") }

    private var fm: FileManager { .default }

    // MARK: - Config

    func config() -> [String: Any] {
        guard let data = fm.contents(atPath: "\(home)/config.json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    func writeConfig(_ config: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: URL(fileURLWithPath: "\(home)/config.json"))
    }

    var tld: String { config()["tld"] as? String ?? "test" }

    /// Parked folders, without Valet's internal `Sites` folder.
    var parkedPaths: [String] {
        let paths = config()["paths"] as? [String] ?? []
        return ValetModel.userParkedPaths(paths, configDir: home)
    }

    // MARK: - Reading

    func domain(_ site: String) -> String { "\(site).\(tld)" }
    func nginxPath(_ site: String) -> String { "\(nginxDir)/\(domain(site))" }
    func certPath(_ site: String, _ ext: String) -> String { "\(certificatesDir)/\(domain(site)).\(ext)" }
    func isSecured(_ site: String) -> Bool { fm.fileExists(atPath: certPath(site, "crt")) }
    func nginxConf(_ site: String) -> String? { try? String(contentsOfFile: nginxPath(site), encoding: .utf8) }

    /// Linked sites: `~/.config/valet/Sites/<name>` symlinks.
    func links() -> [(name: String, path: String)] {
        let names = (try? fm.contentsOfDirectory(atPath: sitesDir)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().compactMap { name in
            guard let target = try? fm.destinationOfSymbolicLink(atPath: "\(sitesDir)/\(name)") else { return nil }
            let absolute = target.hasPrefix("/") ? target : URL(fileURLWithPath: sitesDir).appendingPathComponent(target).standardizedFileURL.path
            return (name, absolute)
        }
    }

    /// Sites served from parked folders (one per subfolder).
    func parkedSites() -> [(name: String, path: String)] {
        parkedPaths.flatMap { parent -> [(name: String, path: String)] in
            let entries = (try? fm.contentsOfDirectory(atPath: parent)) ?? []
            return entries.filter { !$0.hasPrefix(".") }.sorted().compactMap { entry in
                var isDir: ObjCBool = false
                let path = "\(parent)/\(entry)"
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
                return (entry.lowercased(), path)
            }
        }
    }

    /// Linked then parked sites, in the same shape as `valet links` / `valet parked`.
    /// - Parameter globalPHP: label of the global PHP, e.g. `php@8.5` (as `valet links` shows it).
    func sites(globalPHP: String?) -> [ValetSite] {
        let fallbackPHP = globalPHP ?? ""
        func site(_ name: String, _ path: String, parked: Bool) -> ValetSite {
            let secured = isSecured(name)
            let php = nginxConf(name).flatMap(ValetFiles.isolatedVersion) ?? fallbackPHP
            return ValetSite(name: name, secured: secured, url: "\(secured ? "https" : "http")://\(domain(name))",
                             path: path, php: php, parked: parked)
        }
        let linked = links().map { site($0.name, $0.path, parked: false) }
        let names = Set(linked.map(\.name))
        let proxied = Set(proxies().map(\.name))
        let parked = parkedSites().filter { !names.contains($0.name) && !proxied.contains($0.name) }
            .map { site($0.name, $0.path, parked: true) }
        return linked + parked
    }

    /// Proxies: Nginx site files containing `proxy_pass`.
    func proxies() -> [ValetProxy] {
        let files = (try? fm.contentsOfDirectory(atPath: nginxDir)) ?? []
        let suffix = ".\(tld)"
        return files.filter { $0.hasSuffix(suffix) }.sorted().compactMap { file in
            guard let conf = try? String(contentsOfFile: "\(nginxDir)/\(file)", encoding: .utf8),
                  let host = ValetFiles.proxyHost(conf) else { return nil }
            let name = String(file.dropLast(suffix.count))
            let secured = conf.contains(":443 ssl")
            return ValetProxy(name: name, secured: secured, url: "\(secured ? "https" : "http")://\(file)", host: host)
        }
    }

    /// Version of the pool `valet.sock` points to (`valet85.sock` → `8.5`).
    var globalSocketVersion: String? {
        guard let target = try? fm.destinationOfSymbolicLink(atPath: "\(home)/valet.sock") else { return nil }
        let digits = URL(fileURLWithPath: target).lastPathComponent.filter(\.isNumber)
        guard digits.count >= 2 else { return nil }
        return "\(digits.prefix(1)).\(digits.dropFirst())"
    }

    /// PHP versions the Nginx site files point to (`valet83.sock` → `8.3`).
    func isolatedVersions() -> Set<String> {
        let files = (try? fm.contentsOfDirectory(atPath: nginxDir)) ?? []
        var versions = Set<String>()
        for file in files where !file.hasPrefix(".") {
            if let conf = try? String(contentsOfFile: "\(nginxDir)/\(file)", encoding: .utf8),
               let version = ValetFiles.isolatedVersion(conf) {
                versions.insert(version.replacingOccurrences(of: "php@", with: ""))
            }
        }
        return versions
    }

    // MARK: - Pure helpers (tested)

    /// `# ISOLATED_PHP_VERSION=php@8.3` on the first line → `php@8.3`.
    static func isolatedVersion(_ conf: String) -> String? {
        guard let first = conf.split(separator: "\n", maxSplits: 1).first, first.hasPrefix(isolatedMarker) else { return nil }
        let value = first.dropFirst(isolatedMarker.count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    static func proxyHost(_ conf: String) -> String? {
        guard let range = conf.range(of: #"proxy_pass\s+([^;\s]+);"#, options: .regularExpression) else { return nil }
        return conf[range].replacingOccurrences(of: "proxy_pass", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ;\t"))
    }

    /// `php@8.3` / `8.3` → `valet83.sock`
    static func socketName(_ version: String) -> String {
        "valet\(version.filter(\.isNumber)).sock"
    }

    /// Fills a Valet stub.
    func render(_ stub: String, site: String? = nil, extra: [String: String] = [:]) -> String {
        var text = stub
        let loopback = config()["loopback"] as? String ?? "127.0.0.1"
        var values = ["VALET_HOME_PATH": home, "VALET_SERVER_PATH": serverPath, "VALET_STATIC_PREFIX": Self.staticPrefix,
                      "VALET_LOOPBACK": loopback]
        if let site {
            values["VALET_SITE"] = domain(site)
            values["VALET_CERT"] = certPath(site, "crt")
            values["VALET_KEY"] = certPath(site, "key")
        }
        values.merge(extra) { _, new in new }
        for (key, value) in values.sorted(by: { $0.key.count > $1.key.count }) {
            text = text.replacingOccurrences(of: key, with: value)
        }
        return text
    }

    func stub(_ name: String) throws -> String {
        try String(contentsOfFile: "\(valetPackage)/cli/stubs/\(name)", encoding: .utf8)
    }

    // MARK: - Writing (rootless mode)

    func link(_ name: String, to folder: String) throws {
        try fm.createDirectory(atPath: sitesDir, withIntermediateDirectories: true)
        let path = "\(sitesDir)/\(name)"
        if (try? fm.destinationOfSymbolicLink(atPath: path)) != nil { try fm.removeItem(atPath: path) }
        try fm.createSymbolicLink(atPath: path, withDestinationPath: folder)
    }

    func unlink(_ name: String) throws {
        if isSecured(name) { try unsecure(name) }
        try? fm.removeItem(atPath: nginxPath(name))
        try fm.removeItem(atPath: "\(sitesDir)/\(name)")
    }

    func park(_ folder: String) throws {
        var config = config()
        var paths = config["paths"] as? [String] ?? []
        if !paths.contains(folder) { paths.append(folder) }
        config["paths"] = paths
        try writeConfig(config)
    }

    func forget(_ folder: String) throws {
        var config = config()
        config["paths"] = (config["paths"] as? [String] ?? []).filter { $0 != folder }
        try writeConfig(config)
    }

    /// Like `valet secure`: certificate signed by Valet's CA, secure Nginx file, isolation kept.
    func secure(_ site: String) async throws {
        try await ensureCA()
        try fm.createDirectory(atPath: certificatesDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: nginxDir, withIntermediateDirectories: true)
        let isolated = nginxConf(site).flatMap(Self.isolatedVersion)
        let conf = certPath(site, "conf"), key = certPath(site, "key"), csr = certPath(site, "csr"), crt = certPath(site, "crt")
        try render(try stub("openssl.conf"), extra: ["VALET_DOMAIN": domain(site)]).write(toFile: conf, atomically: true, encoding: .utf8)
        try await run("/usr/bin/openssl", ["genrsa", "-out", key, "2048"])
        try await run("/usr/bin/openssl", ["req", "-new", "-key", key, "-out", csr, "-subj",
                                           "/C=/ST=/O=/localityName=/commonName=\(domain(site))/organizationalUnitName=/emailAddress=\(domain(site))@laravel.valet/"])
        var sign = ["x509", "-req", "-sha256", "-days", "396", "-CA", caPem, "-CAkey", caKey]
        let serial = "\(caDir)/LaravelValetCASelfSigned.srl"
        sign += fm.fileExists(atPath: serial) ? ["-CAserial", serial] : ["-CAserial", serial, "-CAcreateserial"]
        sign += ["-in", csr, "-out", crt, "-extensions", "v3_req", "-extfile", conf]
        try await run("/usr/bin/openssl", sign)
        var siteConf = render(try stub("secure.valet.conf"), site: site)
        if let isolated { siteConf = Self.withSocket(siteConf, version: isolated) }
        try siteConf.write(toFile: nginxPath(site), atomically: true, encoding: .utf8)
    }

    func unsecure(_ site: String) throws {
        let isolated = nginxConf(site).flatMap(Self.isolatedVersion)
        for ext in ["crt", "key", "csr", "conf"] { try? fm.removeItem(atPath: certPath(site, ext)) }
        try? fm.removeItem(atPath: nginxPath(site))
        if let isolated { try isolate(site, version: isolated) }
    }

    func isolate(_ site: String, version: String) throws {
        try fm.createDirectory(atPath: nginxDir, withIntermediateDirectories: true)
        let siteConf: String
        if let existing = nginxConf(site) {
            siteConf = Self.withSocket(existing, version: version)
        } else {
            siteConf = render(try stub("site.valet.conf"), site: site,
                              extra: ["VALET_PHP_FPM_SOCKET": Self.socketName(version), "VALET_ISOLATED_PHP_VERSION": version])
        }
        try siteConf.write(toFile: nginxPath(site), atomically: true, encoding: .utf8)
    }

    func unisolate(_ site: String) throws {
        if isSecured(site) {
            try render(try stub("secure.valet.conf"), site: site).write(toFile: nginxPath(site), atomically: true, encoding: .utf8)
        } else {
            try? fm.removeItem(atPath: nginxPath(site))
        }
    }

    func proxy(_ site: String, host: String, secure: Bool) async throws {
        try fm.createDirectory(atPath: nginxDir, withIntermediateDirectories: true)
        if secure {
            try await self.secure(site)
            try render(try stub("secure.proxy.valet.conf"), site: site, extra: ["VALET_PROXY_HOST": host])
                .write(toFile: nginxPath(site), atomically: true, encoding: .utf8)
        } else {
            try render(try stub("proxy.valet.conf"), site: site, extra: ["VALET_PROXY_HOST": host])
                .write(toFile: nginxPath(site), atomically: true, encoding: .utf8)
        }
    }

    func unproxy(_ site: String) throws {
        for ext in ["crt", "key", "csr", "conf"] { try? fm.removeItem(atPath: certPath(site, ext)) }
        try? fm.removeItem(atPath: nginxPath(site))
    }

    /// Valet's `replaceSockFile`: point the site at `valetXY.sock` and mark the version on line 1.
    static func withSocket(_ conf: String, version: String) -> String {
        var text = conf.replacingOccurrences(of: #"valet[0-9]*\.sock"#, with: socketName(version), options: .regularExpression)
        text = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix(isolatedMarker) }
            .joined(separator: "\n")
        return "\(isolatedMarker)\(version)\n" + text
    }

    /// Creates Valet's certificate authority if it does not exist yet (it is trusted by the one-time setup).
    func ensureCA() async throws {
        guard !fm.fileExists(atPath: caPem) else { return }
        try fm.createDirectory(atPath: caDir, withIntermediateDirectories: true)
        try await run("/usr/bin/openssl", ["req", "-new", "-newkey", "rsa:2048", "-days", "7300", "-nodes", "-x509",
                                           "-subj", "/C=/ST=/O=Laravel Valet CA/localityName=/commonName=Laravel Valet CA Self Signed CN/organizationalUnitName=Developers/emailAddress=rootcertificate@laravel.valet/",
                                           "-keyout", caKey, "-out", caPem])
    }

    private func run(_ executable: String, _ args: [String]) async throws {
        let result = await Shell.run(executable, args)
        guard result.succeeded else { throw RootlessError.command(result.output) }
    }
}

enum RootlessError: LocalizedError {
    case command(String)
    case start(String)

    var errorDescription: String? {
        switch self {
        case let .command(output): return output
        case let .start(output): return output
        }
    }
}
