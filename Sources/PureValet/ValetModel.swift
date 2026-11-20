import AppKit
import Foundation
import Observation
import ServiceManagement

struct ValetSite: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let secured: Bool
    let url: String
    let path: String
    let php: String
    /// Site served from a parked folder (`valet park`): it cannot be unlinked on its own.
    var parked = false
}

struct ValetProxy: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let secured: Bool
    let url: String
    let host: String
}

/// An installed Homebrew PHP formula (e.g. `php@8.4`).
struct PHPFormula: Identifiable, Hashable {
    var id: String { formula }
    let formula: String
    let version: String

    var label: String { "PHP \(version)  (\(formula))" }
}

/// A component shown in the "Versions" list.
struct ComponentVersion: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let version: String?
}

enum InstallState: Equatable {
    case unknown
    case notInstalled
    case installed(binary: String)
}

/// Valet state and actions. No timer: state is refreshed when the menu or the settings
/// window opens and after each action. Nothing runs while the app is idle or after it quits.
/// User preferences (UserDefaults).
enum Preferences {
    static let startOnLaunchKey = "startServicesOnLaunch"
    static let stopOnQuitKey = "stopServicesOnQuit"

    static func register() {
        UserDefaults.standard.register(defaults: [startOnLaunchKey: false, stopOnQuitKey: true, Updater.autoCheckKey: true])
    }

    static var startOnLaunch: Bool { UserDefaults.standard.bool(forKey: startOnLaunchKey) }
    static var stopOnQuit: Bool { UserDefaults.standard.bool(forKey: stopOnQuitKey) }
}

@MainActor
@Observable
final class ValetModel {
    /// The app's single model, shared by the menu, the settings window and the app delegate.
    static let shared = ValetModel()

    var install: InstallState = .unknown
    var running: Bool?
    var sites: [ValetSite] = []
    var proxies: [ValetProxy] = []
    var parkedPaths: [String] = []
    var phpFormulas: [PHPFormula] = []
    var globalPHP: String?
    var tld = "test"
    var valetVersion: String?
    var versions: [ComponentVersion] = []
    var trusted = false
    var mariadbInstalled = false
    var mariadbRunning: Bool?
    var yerdDetected = false
    /// Version of the phpMyAdmin copy managed by PureValet, nil if not installed.
    var phpMyAdminVersion: String?
    /// Latest phpMyAdmin release, fetched when the settings window opens.
    var phpMyAdminLatest: PhpMyAdminRelease?

    /// Site name → true when it answers with a non-error HTTP status, false otherwise.
    var siteHealth: [String: Bool] = [:]
    var launchAtLogin = SMAppService.mainApp.status == .enabled

    var busyLabel: String?
    var lastMessage: String?
    var lastOutput = ""
    var lastFailed = false

    private var currentRefresh: Task<Void, Never>?
    private var lastRefresh: Date?

    init() {
        // Refresh when the user opens the menu bar menu (no timer).
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let last = self.lastRefresh, Date().timeIntervalSince(last) < 3 { return }
                Task { await self.refresh() }
                Task { await Updater.shared.checkIfDue() }
            }
        }
        Task { await refresh() }
    }

    static let brew = "\(Shell.brewPrefix)/bin/brew"
    private static let home = Shell.home
    static let valetConfigDir = "\(Shell.home)/.config/valet"

    var isInstalled: Bool {
        if case .installed = install { return true }
        return false
    }

    var menuBarSymbol: String {
        switch install {
        case .unknown: return "v.circle"
        case .notInstalled: return "v.circle.badge.questionmark"
        case .installed: return running == true ? "v.circle.fill" : "v.circle"
        }
    }

    var statusText: String {
        if let busy = busyLabel { return "\(busy)…" }
        switch install {
        case .unknown: return String(localized: "Checking…")
        case .notInstalled: return String(localized: "Valet not installed")
        case .installed:
            switch running {
            case .some(true): return String(localized: "Valet running")
            case .some(false): return String(localized: "Valet stopped")
            case .none: return String(localized: "Unknown state")
            }
        }
    }

    var valetBinary: String? {
        if case let .installed(binary) = install { return binary }
        return nil
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    func displayURL(_ site: ValetSite) -> String {
        site.url.isEmpty ? "\(site.secured ? "https" : "http")://\(site.name).\(tld)" : site.url
    }

    func displayURL(_ proxy: ValetProxy) -> String {
        proxy.url.isEmpty ? "\(proxy.secured ? "https" : "http")://\(proxy.name).\(tld)" : proxy.url
    }

    // MARK: - Detection

    /// `valet install` symlinks Valet into Homebrew's `bin`, and `valet trust` only whitelists that path
    /// in sudoers (Valet re-runs itself with sudo using the path it was called with). So the Homebrew
    /// symlink comes first; the Composer paths are fallbacks for a not-yet-installed Valet.
    private static func locateValet() -> String? {
        let candidates = [
            "\(Shell.brewPrefix)/bin/valet",
            "/opt/homebrew/bin/valet",
            "/usr/local/bin/valet",
            "\(home)/.composer/vendor/bin/valet",
            "\(home)/.config/composer/vendor/bin/valet",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Version of a Homebrew formula, read from its `opt` symlink (instant, no `brew` call).
    nonisolated static func formulaVersion(_ name: String) -> String? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: "\(Shell.brewPrefix)/opt/\(name)") else { return nil }
        return versionFromCellarPath(target)
    }

    /// `../Cellar/php@8.4/8.4.27_1` → `8.4.27`
    nonisolated static func versionFromCellarPath(_ path: String) -> String? {
        guard let last = path.split(separator: "/").last else { return nil }
        return last.split(separator: "_").first.map(String.init)
    }

    /// Reads PHP formulae from `<prefix>/opt` without running `brew` (instant).
    private static func scanPHPFormulas() -> (formulas: [PHPFormula], global: String?) {
        let fm = FileManager.default
        let optDir = "\(Shell.brewPrefix)/opt"
        var byFormula: [String: PHPFormula] = [:]
        let entries = (try? fm.contentsOfDirectory(atPath: optDir)) ?? []
        for entry in entries where entry == "php" || entry.hasPrefix("php@") {
            guard let target = try? fm.destinationOfSymbolicLink(atPath: "\(optDir)/\(entry)") else { continue }
            let parts = target.split(separator: "/")
            guard parts.count >= 2 else { continue }
            let formula = String(parts[parts.count - 2])
            let full = versionFromCellarPath(target) ?? ""
            let short = full.split(separator: ".").prefix(2).joined(separator: ".")
            byFormula[formula] = PHPFormula(formula: formula, version: short)
        }
        var global: String?
        if let target = try? fm.destinationOfSymbolicLink(atPath: "\(Shell.brewPrefix)/bin/php") {
            let parts = target.split(separator: "/")
            if let cellar = parts.firstIndex(of: "Cellar"), cellar + 1 < parts.count {
                global = String(parts[cellar + 1])
            }
        }
        let sorted = byFormula.values.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
        return (sorted, global)
    }

    private static func readTLD() -> String {
        let url = URL(fileURLWithPath: "\(valetConfigDir)/config.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tld = json["tld"] as? String else { return "test" }
        return tld
    }

    // MARK: - Refresh

    /// Refreshes the state. A call made while a refresh is running waits for it instead of returning
    /// early, so callers (snapshot, actions) always see fresh data.
    func refresh() async {
        if let running = currentRefresh {
            await running.value
            return
        }
        let task = Task { await performRefresh() }
        currentRefresh = task
        await task.value
        currentRefresh = nil
        lastRefresh = Date()
    }

    private func performRefresh() async {

        yerdDetected = FileManager.default.isExecutableFile(atPath: "\(Self.home)/.local/bin/yerd")
        let php = Self.scanPHPFormulas()
        phpFormulas = php.formulas
        globalPHP = php.global
        mariadbInstalled = FileManager.default.fileExists(atPath: "\(Shell.brewPrefix)/opt/mariadb")
        trusted = FileManager.default.fileExists(atPath: "/etc/sudoers.d/valet")
        phpMyAdminVersion = PhpMyAdmin.installedVersion
        launchAtLogin = SMAppService.mainApp.status == .enabled

        async let mariadb = mariadbInstalled ? Self.queryMariaDB() : nil

        if let binary = Self.locateValet() {
            install = .installed(binary: binary)
            tld = Self.readTLD()
            async let status = Shell.run(binary, ["status"])
            // `valet status` needs sudo in Valet 4.13+: without `valet trust` it fails even when
            // Valet runs. The process list is checked too, so the state is right either way.
            async let processes = Shell.run("/bin/ps", ["-axo", "comm="])
            async let links = Shell.run(binary, ["links"])
            async let parked = Shell.run(binary, ["parked"])
            async let proxiesOut = Shell.run(binary, ["proxies"])
            async let paths = Shell.run(binary, ["paths"])
            // The Valet version never changes while the app runs: ask once.
            async let version = valetVersion == nil ? Shell.run(binary, ["--version"]) : nil
            let (s, l, pk, p, pa, v, ps) = await (status, links, parked, proxiesOut, paths, version, processes)
            running = s.succeeded || Self.valetServicesRunning(ps.output)
            // A failed command (e.g. two `valet` runs racing) keeps the last known list instead of emptying it.
            if l.succeeded && pk.succeeded {
                let linked = Self.parseSites(l.output)
                let linkedNames = Set(linked.map(\.name))
                sites = linked + Self.parseSites(pk.output, parked: true).filter { !linkedNames.contains($0.name) }
            }
            if p.succeeded { proxies = Self.parseProxies(p.output) }
            if pa.succeeded {
                parkedPaths = Self.userParkedPaths(Self.parsePaths(pa.output), configDir: Self.valetConfigDir)
            }
            if let v, v.succeeded { valetVersion = Self.parseValetVersion(v.output) }
        } else {
            install = .notInstalled
            running = nil
            sites = []
            proxies = []
            parkedPaths = []
            valetVersion = nil
        }
        versions = [
            ComponentVersion(name: "PureValet", version: appVersion),
            ComponentVersion(name: "Laravel Valet", version: valetVersion),
            ComponentVersion(name: "PHP", version: globalPHP.flatMap { Self.formulaVersion($0) }),
            ComponentVersion(name: "nginx", version: Self.formulaVersion("nginx")),
            ComponentVersion(name: "dnsmasq", version: Self.formulaVersion("dnsmasq")),
            ComponentVersion(name: "Composer", version: Self.formulaVersion("composer")),
            ComponentVersion(name: "MariaDB", version: Self.formulaVersion("mariadb")),
        ]
        mariadbRunning = await mariadb
        if running == true {
            await checkSites()
        } else {
            siteHealth = [:]
        }
    }

    private static func queryMariaDB() async -> Bool? {
        let result = await Shell.run(brew, ["services", "info", "mariadb", "--json"])
        guard result.succeeded,
              let data = result.output.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first else { return nil }
        return first["running"] as? Bool
    }

    // MARK: - Site health

    /// One HEAD request per site, in parallel, 3 s timeout. Only while Valet runs, only on refresh.
    private func checkSites() async {
        let targets = sites.compactMap { site in URL(string: displayURL(site)).map { (site.name, $0) } }
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let results = await withTaskGroup(of: (String, Bool).self) { group in
            for (name, url) in targets {
                group.addTask {
                    var request = URLRequest(url: url, timeoutInterval: 3)
                    request.httpMethod = "HEAD"
                    guard let response = try? await session.data(for: request).1 as? HTTPURLResponse else {
                        return (name, false)
                    }
                    return (name, Self.isHealthy(statusCode: response.statusCode))
                }
            }
            var health: [String: Bool] = [:]
            for await (name, ok) in group { health[name] = ok }
            return health
        }
        siteHealth = results
    }

    /// Any answer below 500 means the site works (redirects to a login page included).
    nonisolated static func isHealthy(statusCode: Int) -> Bool {
        (100..<500).contains(statusCode)
    }

    var valetDot: StatusDot.State {
        switch install {
        case .installed: return running == true ? .ok : .down
        case .notInstalled: return .down
        case .unknown: return .unknown
        }
    }

    func dot(for site: ValetSite) -> StatusDot.State {
        guard running == true, let ok = siteHealth[site.name] else { return running == true ? .unknown : .down }
        return ok ? .ok : .down
    }

    // MARK: - Parsing Valet output

    /// Valet prints Symfony tables (`| Site | SSL | URL | … |`). Columns are read by name.
    nonisolated static func parseTable(_ text: String) -> [[String: String]] {
        let rows = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("|") }
            .map { line in
                line.split(separator: "|", omittingEmptySubsequences: false)
                    .dropFirst().dropLast()
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
        guard let header = rows.first else { return [] }
        return rows.dropFirst().map { cells in
            var dict: [String: String] = [:]
            for (i, key) in header.enumerated() where i < cells.count {
                dict[key.lowercased()] = cells[i]
            }
            return dict
        }
    }

    nonisolated private static func isSecure(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else { return false }
        return value == "x" || value == "✓" || value == "yes" || value == "true"
    }

    nonisolated static func parseSites(_ text: String, parked: Bool = false) -> [ValetSite] {
        parseTable(text).compactMap { row in
            guard let name = row["site"], !name.isEmpty else { return nil }
            return ValetSite(
                name: name,
                secured: isSecure(row["ssl"]),
                url: row["url"] ?? "",
                path: row["path"] ?? "",
                php: row["php version"] ?? row["php"] ?? "",
                parked: parked
            )
        }
    }

    nonisolated static func parseProxies(_ text: String) -> [ValetProxy] {
        parseTable(text).compactMap { row in
            guard let name = row["site"], !name.isEmpty else { return nil }
            return ValetProxy(name: name, secured: isSecure(row["ssl"]), url: row["url"] ?? "", host: row["host"] ?? "")
        }
    }

    /// True when Valet's three services appear in `ps -axo comm=`: nginx, PHP-FPM's `valet` pool and dnsmasq.
    nonisolated static func valetServicesRunning(_ psOutput: String) -> Bool {
        let lines = psOutput.split(separator: "\n")
        let nginx = lines.contains { $0.hasPrefix("nginx: master process") }
        let phpFPM = lines.contains { $0.hasPrefix("php-fpm: pool valet") }
        let dnsmasq = lines.contains { $0.hasSuffix("/dnsmasq") || $0 == "dnsmasq" }
        return nginx && phpFPM && dnsmasq
    }

    /// Valet registers its own `Sites` folder (where linked sites live) as a parked path.
    /// It is hidden so it cannot be "forgotten" by mistake, which would break every linked site.
    nonisolated static func userParkedPaths(_ paths: [String], configDir: String) -> [String] {
        let valetSites = URL(fileURLWithPath: configDir).appendingPathComponent("Sites").standardizedFileURL.path
        return paths.filter { URL(fileURLWithPath: $0).standardizedFileURL.path != valetSites }
    }

    /// `valet paths` prints a JSON array of parked folders.
    nonisolated static func parsePaths(_ text: String) -> [String] {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let paths = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return paths
    }

    /// `Laravel Valet 4.8.1` → `4.8.1`
    nonisolated static func parseValetVersion(_ text: String) -> String? {
        text.split(whereSeparator: \.isWhitespace)
            .last { $0.first?.isNumber == true }
            .map(String.init)
    }

    // MARK: - Actions

    private func valet(_ label: String, _ args: [String], cwd: URL? = nil) async {
        guard case let .installed(binary) = install else {
            report(label, CommandResult(status: 1, output: String(localized: "Valet is not installed.")))
            return
        }
        await offerTrustIfNeeded(binary: binary)
        await execute(label) { await Shell.run(binary, args, cwd: cwd, allowSudoPrompt: true) }
    }

    private static let dontOfferTrustKey = "dontOfferValetTrust"

    /// Without `valet trust`, every Valet action asks for the password. Instead of that, offer once
    /// to run `valet trust`: one last password, then no more prompts.
    private func offerTrustIfNeeded(binary: String) async {
        guard !trusted, !Snapshot.isActive,
              !UserDefaults.standard.bool(forKey: Self.dontOfferTrustKey) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Stop the password prompts?")
        alert.informativeText = String(localized: "Valet asks for your password on almost every action. PureValet can run `valet trust` once: you type your password one last time, then starting, stopping, HTTPS and the other Valet commands no longer ask for it.")
        alert.addButton(withTitle: String(localized: "Enable (recommended)"))
        alert.addButton(withTitle: String(localized: "Not now"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don't ask again")
        let answer = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: Self.dontOfferTrustKey)
        }
        guard answer == .alertFirstButtonReturn else { return }
        let result = await Shell.run(binary, ["trust"], allowSudoPrompt: true)
        trusted = FileManager.default.fileExists(atPath: "/etc/sudoers.d/valet")
        if !result.succeeded { report(String(localized: "Enabling password-free commands"), result) }
    }

    private func execute(_ label: String, _ work: () async -> CommandResult) async {
        guard busyLabel == nil else { return }
        busyLabel = label
        let result = await work()
        busyLabel = nil
        report(label, result)
        await refresh()
    }

    private func report(_ label: String, _ result: CommandResult) {
        lastOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        lastFailed = !result.succeeded
        if result.succeeded {
            lastMessage = String(localized: "\(label): done")
        } else if Self.isSudoFailure(result.output) {
            lastMessage = String(localized: "\(label): administrator rights denied or password cancelled. Try again, or run the command in Terminal.")
        } else {
            let code = String(result.status)
            lastMessage = String(localized: "\(label): failed (exit code \(code))")
        }
    }

    private static func isSudoFailure(_ output: String) -> Bool {
        let o = output.lowercased()
        return o.contains("sudo:") && (o.contains("password") || o.contains("askpass") || o.contains("terminal"))
    }

    func start() async { await valet(String(localized: "Starting Valet"), ["start"]) }
    func stop() async { await valet(String(localized: "Stopping Valet"), ["stop"]) }
    func restart() async { await valet(String(localized: "Restarting Valet"), ["restart"]) }
    func trust() async { await valet(String(localized: "Enabling password-free commands"), ["trust"]) }

    func useGlobalPHP(_ formula: String) async {
        await valet(String(localized: "Global PHP → \(formula)"), ["use", formula])
    }

    func isolate(_ site: ValetSite, formula: String) async {
        await valet("\(site.name) → \(formula)", ["isolate", formula, "--site=\(site.name)"])
    }

    func unisolate(_ site: ValetSite) async {
        await valet(String(localized: "\(site.name) → global PHP"), ["unisolate", "--site=\(site.name)"])
    }

    func setSecure(_ site: ValetSite, _ secure: Bool) async {
        let label = secure ? String(localized: "HTTPS for \(site.name)") : String(localized: "HTTP for \(site.name)")
        await valet(label, [secure ? "secure" : "unsecure", site.name])
    }

    func unlink(_ site: ValetSite) async {
        await valet(String(localized: "Unlink \(site.name)"), ["unlink", site.name])
    }

    private func chooseFolder(prompt: String, message: String) -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Asks for a folder, then runs `valet link <name>` inside it.
    func chooseAndLinkFolder() async {
        guard let folder = chooseFolder(prompt: String(localized: "Link"), message: String(localized: "Choose the site folder to link to Valet")) else { return }
        let name = Self.slug(folder.lastPathComponent)
        await valet(String(localized: "Link \(name)"), ["link", name], cwd: folder)
    }

    /// Asks for a folder, then runs `valet park` inside it: each subfolder becomes a site.
    func chooseAndParkFolder() async {
        guard let folder = chooseFolder(prompt: String(localized: "Park"), message: String(localized: "Choose a folder: each subfolder will be served as a site")) else { return }
        await valet(String(localized: "Park \(folder.lastPathComponent)"), ["park"], cwd: folder)
    }

    func forget(_ path: String) async {
        let name = URL(fileURLWithPath: path).lastPathComponent
        await valet(String(localized: "Forget \(name)"), ["forget", path])
    }

    func addProxy(name: String, port: Int, secure: Bool) async {
        let site = Self.slug(name)
        guard !site.isEmpty, (1...65535).contains(port) else {
            report(String(localized: "Proxy"), CommandResult(status: 1, output: String(localized: "Invalid name or port.")))
            return
        }
        var args = ["proxy", site, "http://127.0.0.1:\(port)"]
        if secure { args.append("--secure") }
        await valet("Proxy \(site) → :\(port)", args)
    }

    func unproxy(_ proxy: ValetProxy) async {
        await valet("Unproxy \(proxy.name)", ["unproxy", proxy.name])
    }

    func setMariaDB(_ start: Bool) async {
        let label = start ? String(localized: "Starting MariaDB") : String(localized: "Stopping MariaDB")
        await execute(label) {
            // `run` starts MariaDB without registering it to launch at login.
            await Shell.run(Self.brew, ["services", start ? "run" : "stop", "mariadb"])
        }
    }

    var anyServiceRunning: Bool { running == true || mariadbRunning == true }
    var anyServiceStopped: Bool { (isInstalled && running != true) || (mariadbInstalled && mariadbRunning != true) }

    /// Starts Valet (nginx, PHP-FPM, dnsmasq) and MariaDB if installed.
    func startAll() async {
        if isInstalled && running != true { await start() }
        if mariadbInstalled && mariadbRunning != true { await setMariaDB(true) }
    }

    /// Stops Valet and MariaDB.
    func stopAll() async {
        if isInstalled && running == true { await stop() }
        if mariadbInstalled && mariadbRunning == true { await setMariaDB(false) }
    }

    /// Called when the app quits: stops whatever is still running so nothing is left in the background
    /// (and nothing restarts at the next boot, since `valet stop` unregisters the launchd services).
    /// Ignores the busy flag on purpose: quitting must always proceed.
    func stopEverythingForQuit() async {
        await refresh()
        if case let .installed(binary) = install, running == true {
            _ = await Shell.run(binary, ["stop"], allowSudoPrompt: true)
        }
        if mariadbInstalled, mariadbRunning == true {
            _ = await Shell.run(Self.brew, ["services", "stop", "mariadb"])
        }
    }

    // MARK: - phpMyAdmin

    var phpMyAdminSite: ValetSite? { sites.first { $0.name == PhpMyAdmin.siteName } }
    var phpMyAdminAvailable: Bool { phpMyAdminVersion != nil || phpMyAdminSite != nil }
    var phpMyAdminUpdateAvailable: Bool {
        guard let installed = phpMyAdminVersion, let latest = phpMyAdminLatest?.version else { return false }
        return Updater.isVersion(latest, newerThan: installed)
    }

    func fetchPhpMyAdminLatest() async {
        if let release = await PhpMyAdmin.fetchLatest() { phpMyAdminLatest = release }
    }

    func openPhpMyAdmin() {
        let url = phpMyAdminSite.map(displayURL) ?? "https://\(PhpMyAdmin.siteName).\(tld)"
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }

    /// Installs (or updates) the built-in phpMyAdmin and serves it as `phpmyadmin.<tld>` over HTTPS,
    /// on a PHP version it supports.
    func installPhpMyAdmin(openWhenDone: Bool = true) async {
        guard busyLabel == nil, case let .installed(binary) = install else { return }
        let label = phpMyAdminVersion == nil ? String(localized: "Installing phpMyAdmin") : String(localized: "Updating phpMyAdmin")
        await offerTrustIfNeeded(binary: binary)
        busyLabel = label
        var output: [String] = []
        var result = CommandResult(status: 0, output: "")
        do {
            guard let release = await PhpMyAdmin.fetchLatest() else { throw PhpMyAdmin.InstallError.download }
            phpMyAdminLatest = release
            try await PhpMyAdmin.install(release)
            output.append("phpMyAdmin \(release.version) → \(PhpMyAdmin.directory.path)")
            var steps: [[String]] = [["link", PhpMyAdmin.siteName]]
            if let php = PhpMyAdmin.compatiblePHP(constraint: release.phpConstraint, installed: phpFormulas, global: globalPHP) {
                steps.append(["isolate", php, "--site=\(PhpMyAdmin.siteName)"])
            }
            if phpMyAdminSite?.secured != true {
                steps.append(["secure", PhpMyAdmin.siteName])
            }
            for args in steps {
                let step = await Shell.run(binary, args, cwd: PhpMyAdmin.directory, allowSudoPrompt: true)
                output.append("$ valet \(args.joined(separator: " "))\n\(step.output)")
                if !step.succeeded {
                    result = CommandResult(status: step.status, output: output.joined(separator: "\n"))
                    break
                }
            }
            if result.succeeded { result = CommandResult(status: 0, output: output.joined(separator: "\n")) }
        } catch {
            result = CommandResult(status: 1, output: (output + [error.localizedDescription]).joined(separator: "\n"))
        }
        busyLabel = nil
        report(label, result)
        await refresh()
        if result.succeeded && openWhenDone { openPhpMyAdmin() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastFailed = false
            lastMessage = enabled ? String(localized: "PureValet will open at login") : String(localized: "PureValet will no longer open at login")
            lastOutput = ""
        } catch {
            lastFailed = true
            lastMessage = String(localized: "Could not change the login item")
            lastOutput = error.localizedDescription
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Shortcuts (Finder, browser, Terminal)

    func open(_ site: ValetSite) {
        if let url = URL(string: displayURL(site)) { NSWorkspace.shared.open(url) }
    }

    func open(_ proxy: ValetProxy) {
        if let url = URL(string: displayURL(proxy)) { NSWorkspace.shared.open(url) }
    }

    func copyURL(_ site: ValetSite) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayURL(site), forType: .string)
    }

    func reveal(_ path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openInTerminal(_ path: String) {
        guard !path.isEmpty,
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    func openLogs() { openFolder("\(Self.valetConfigDir)/Log") }
    func openConfig() { openFolder(Self.valetConfigDir) }

    private func openFolder(_ path: String) {
        let target = FileManager.default.fileExists(atPath: path) ? path : Self.valetConfigDir
        NSWorkspace.shared.open(URL(fileURLWithPath: target))
    }

    /// Safe Valet site name: lowercase letters, digits and dashes.
    nonisolated static func slug(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let mapped = lowered.map { $0.isLetter && $0.isASCII || $0.isNumber ? $0 : "-" }
        return String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }
}
