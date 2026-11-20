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
    /// Standard (non-admin) account: PureValet runs the services itself (see `RootlessRuntime`).
    var rootless = false
    /// One-time admin setup state for rootless mode.
    var rootlessSetup = RootlessSetup.Status()
    /// Administrator accounts of this Mac (for the setup hint).
    var adminAccounts: [String] = []
    /// Valet's files, located from the installed `valet` binary.
    private(set) var files = ValetFiles()

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
            files = ValetFiles(valetPackage: URL(fileURLWithPath: binary).resolvingSymlinksInPath().deletingLastPathComponent().path)
            tld = files.tld
            rootless = !(await Self.isAdmin())
            if rootless {
                // Standard account: PureValet runs the services itself; the global PHP is the one valet.sock points to.
                if let version = files.globalSocketVersion, let formula = phpFormulas.first(where: { $0.version == version }) {
                    globalPHP = formula.formula
                }
                running = RootlessRuntime.shared.isRunning
                rootlessSetup = await RootlessSetup.status(files: files, formulas: phpFormulas)
                if !rootlessSetup.ready { adminAccounts = await RootlessSetup.adminAccounts() }
            } else {
                // `valet status` needs sudo in Valet 4.13+: without `valet trust` it fails even when
                // Valet runs. The process list is checked too, so the state is right either way.
                async let status = Shell.run(binary, ["status"])
                async let processes = Shell.run("/bin/ps", ["-axo", "comm="])
                let (s, ps) = await (status, processes)
                running = s.succeeded || Self.valetServicesRunning(ps.output)
            }
            // Read Valet's files directly: `valet links/parked/proxies` run sudo internally, which fails
            // on a standard account and needs a cached password otherwise.
            sites = files.sites(globalPHP: globalPHPVersion.map { "php@\($0)" })
            proxies = files.proxies()
            parkedPaths = files.parkedPaths
            // The Valet version never changes while the app runs: ask once (read-only, no sudo).
            if valetVersion == nil {
                let v = await Shell.run(binary, ["--version"])
                if v.succeeded { valetVersion = Self.parseValetVersion(v.output) }
            }
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

    /// Whether the current macOS user is an administrator (Valet needs sudo otherwise).
    static func isAdmin() async -> Bool {
        let result = await Shell.run("/usr/sbin/dsmemberutil", ["checkmembership", "-U", NSUserName(), "-G", "admin"])
        return result.output.contains("is a member")
    }

    /// Global PHP version (`8.5`): the formula Homebrew links, or in rootless mode the one valet.sock uses.
    var globalPHPVersion: String? {
        phpFormulas.first { $0.formula == globalPHP }?.version
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

    /// A site change: through `valet` on an admin account, or directly on Valet's files then a
    /// config reload in rootless mode (no sudo at all).
    private func change(_ label: String, valet args: [String], cwd: URL? = nil,
                        rootless work: @escaping () async throws -> Void) async {
        guard rootless else {
            await valet(label, args, cwd: cwd)
            return
        }
        guard busyLabel == nil else { return }
        busyLabel = label
        var result = CommandResult(status: 0, output: "")
        do {
            try await work()
            try await reloadRootless()
        } catch {
            result = CommandResult(status: 1, output: error.localizedDescription)
        }
        busyLabel = nil
        report(label, result)
        await refresh()
    }

    private func reloadRootless() async throws {
        guard let version = files.globalSocketVersion ?? globalPHPVersion else { return }
        try await RootlessRuntime.shared.reload(files: files, globalVersion: version, formulas: phpFormulas)
    }

    /// `php` → `php@8.5`, `php@8.3` → `php@8.3` (the form Valet writes in its files).
    private func versionedFormula(_ formula: String) -> String {
        if formula.hasPrefix("php@") { return formula }
        return phpFormulas.first { $0.formula == formula }.map { "php@\($0.version)" } ?? formula
    }

    /// Rootless start/stop of nginx, PHP-FPM and dnsmasq.
    private func runRootless(_ label: String, start: Bool) async {
        guard busyLabel == nil else { return }
        busyLabel = label
        var result = CommandResult(status: 0, output: "")
        if start {
            do {
                guard let version = files.globalSocketVersion ?? globalPHPVersion else {
                    throw RootlessError.start(String(localized: "No Homebrew PHP found for the global version."))
                }
                try await RootlessRuntime.shared.start(files: files, globalVersion: version, formulas: phpFormulas)
            } catch {
                result = CommandResult(status: 1, output: error.localizedDescription)
            }
        } else {
            await RootlessRuntime.shared.stop()
        }
        busyLabel = nil
        report(label, result)
        await refresh()
    }

    /// One-time setup with an administrator account (macOS asks for the admin name and password).
    func runRootlessSetup() async {
        guard busyLabel == nil else { return }
        let label = String(localized: "Setting up the no-admin mode")
        busyLabel = label
        try? await files.ensureCA()
        let result = await RootlessSetup.run(files: files, formulas: phpFormulas)
        busyLabel = nil
        report(label, result)
        await refresh()
    }

    private static let dontOfferTrustKey = "dontOfferValetTrust"

    /// Without `valet trust`, every Valet action asks for the password. Instead of that, offer once
    /// to run `valet trust`: one last password, then no more prompts.
    private func offerTrustIfNeeded(binary: String) async {
        guard !trusted, !rootless, !Snapshot.isActive,
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

    func start() async {
        if rootless { await runRootless(String(localized: "Starting Valet"), start: true) } else { await valet(String(localized: "Starting Valet"), ["start"]) }
    }

    func stop() async {
        if rootless { await runRootless(String(localized: "Stopping Valet"), start: false) } else { await valet(String(localized: "Stopping Valet"), ["stop"]) }
    }

    func restart() async {
        if rootless { await runRootless(String(localized: "Restarting Valet"), start: true) } else { await valet(String(localized: "Restarting Valet"), ["restart"]) }
    }
    func trust() async { await valet(String(localized: "Enabling password-free commands"), ["trust"]) }

    func useGlobalPHP(_ formula: String) async {
        let version = phpFormulas.first { $0.formula == formula }?.version
        await change(String(localized: "Global PHP → \(formula)"), valet: ["use", formula]) { [files] in
            guard let version else { return }
            let link = "\(files.home)/valet.sock"
            try? FileManager.default.removeItem(atPath: link)
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "\(files.home)/\(ValetFiles.socketName(version))")
        }
    }

    func isolate(_ site: ValetSite, formula: String) async {
        let versioned = versionedFormula(formula)
        await change("\(site.name) → \(formula)", valet: ["isolate", formula, "--site=\(site.name)"]) { [files] in
            try files.isolate(site.name, version: versioned)
        }
    }

    func unisolate(_ site: ValetSite) async {
        await change(String(localized: "\(site.name) → global PHP"), valet: ["unisolate", "--site=\(site.name)"]) { [files] in
            try files.unisolate(site.name)
        }
    }

    func setSecure(_ site: ValetSite, _ secure: Bool) async {
        let label = secure ? String(localized: "HTTPS for \(site.name)") : String(localized: "HTTP for \(site.name)")
        await change(label, valet: [secure ? "secure" : "unsecure", site.name]) { [files] in
            if secure { try await files.secure(site.name) } else { try files.unsecure(site.name) }
        }
    }

    func unlink(_ site: ValetSite) async {
        await change(String(localized: "Unlink \(site.name)"), valet: ["unlink", site.name]) { [files] in
            try files.unlink(site.name)
        }
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
        await change(String(localized: "Link \(name)"), valet: ["link", name], cwd: folder) { [files] in
            try files.link(name, to: folder.path)
        }
    }

    /// Asks for a folder, then runs `valet park` inside it: each subfolder becomes a site.
    func chooseAndParkFolder() async {
        guard let folder = chooseFolder(prompt: String(localized: "Park"), message: String(localized: "Choose a folder: each subfolder will be served as a site")) else { return }
        await change(String(localized: "Park \(folder.lastPathComponent)"), valet: ["park"], cwd: folder) { [files] in
            try files.park(folder.path)
        }
    }

    func forget(_ path: String) async {
        let name = URL(fileURLWithPath: path).lastPathComponent
        await change(String(localized: "Forget \(name)"), valet: ["forget", path]) { [files] in
            try files.forget(path)
        }
    }

    func addProxy(name: String, port: Int, secure: Bool) async {
        let site = Self.slug(name)
        guard !site.isEmpty, (1...65535).contains(port) else {
            report(String(localized: "Proxy"), CommandResult(status: 1, output: String(localized: "Invalid name or port.")))
            return
        }
        var args = ["proxy", site, "http://127.0.0.1:\(port)"]
        if secure { args.append("--secure") }
        await change("Proxy \(site) → :\(port)", valet: args) { [files] in
            try await files.proxy(site, host: "http://127.0.0.1:\(port)", secure: secure)
        }
    }

    func unproxy(_ proxy: ValetProxy) async {
        await change("Unproxy \(proxy.name)", valet: ["unproxy", proxy.name]) { [files] in
            try files.unproxy(proxy.name)
        }
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
        if rootless {
            await RootlessRuntime.shared.stop()
        } else if case let .installed(binary) = install, running == true {
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
            if rootless {
                for args in steps {
                    switch args[0] {
                    case "link": try files.link(PhpMyAdmin.siteName, to: PhpMyAdmin.directory.path)
                    case "isolate": try files.isolate(PhpMyAdmin.siteName, version: versionedFormula(args[1]))
                    case "secure": try await files.secure(PhpMyAdmin.siteName)
                    default: break
                    }
                    output.append("✓ \(args.joined(separator: " "))")
                }
                try await reloadRootless()
                steps = []
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
