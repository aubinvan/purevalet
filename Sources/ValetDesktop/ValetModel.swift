import AppKit
import Foundation
import Observation

struct ValetSite: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let secured: Bool
    let url: String
    let path: String
    let php: String
}

struct ValetProxy: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let secured: Bool
    let url: String
    let host: String
}

/// Une formule PHP Homebrew installée (ex. `php@8.4`).
struct PHPFormula: Identifiable, Hashable {
    var id: String { formula }
    let formula: String
    let version: String

    var label: String { "PHP \(version)  (\(formula))" }
}

enum InstallState: Equatable {
    case unknown
    case notInstalled
    case installed(binary: String)
}

/// État de Valet et actions. Aucun minuteur : on rafraîchit à l'ouverture du menu
/// et après chaque action, rien ne tourne quand le menu est fermé ou l'appli quittée.
@MainActor
@Observable
final class ValetModel {
    var install: InstallState = .unknown
    var running: Bool?
    var sites: [ValetSite] = []
    var proxies: [ValetProxy] = []
    var phpFormulas: [PHPFormula] = []
    var globalPHP: String?
    var tld = "test"
    var mariadbInstalled = false
    var mariadbRunning: Bool?
    var yerdDetected = false

    var busyLabel: String?
    var lastMessage: String?
    var lastOutput = ""
    var lastFailed = false

    private var isRefreshing = false
    private var lastRefresh: Date?

    init() {
        // Rafraîchit quand l'utilisateur ouvre le menu de la barre de menus (aucun minuteur).
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let last = self.lastRefresh, Date().timeIntervalSince(last) < 3 { return }
                Task { await self.refresh() }
            }
        }
        Task { await refresh() }
    }

    static let brew = "\(Shell.brewPrefix)/bin/brew"
    private static let home = Shell.home

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
        case .unknown: return "Vérification…"
        case .notInstalled: return "Valet non installé"
        case .installed:
            switch running {
            case .some(true): return "Valet démarré"
            case .some(false): return "Valet arrêté"
            case .none: return "État inconnu"
            }
        }
    }

    var valetBinary: String? {
        if case let .installed(binary) = install { return binary }
        return nil
    }

    func displayURL(_ site: ValetSite) -> String {
        site.url.isEmpty ? "\(site.secured ? "https" : "http")://\(site.name).\(tld)" : site.url
    }

    func displayURL(_ proxy: ValetProxy) -> String {
        proxy.url.isEmpty ? "\(proxy.secured ? "https" : "http")://\(proxy.name).\(tld)" : proxy.url
    }

    // MARK: - Détection

    private static func locateValet() -> String? {
        let candidates = [
            "\(home)/.composer/vendor/bin/valet",
            "\(home)/.config/composer/vendor/bin/valet",
            "/opt/homebrew/bin/valet",
            "/usr/local/bin/valet",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Lit les formules PHP depuis <prefix>/opt sans lancer `brew` (instantané).
    private static func scanPHPFormulas() -> (formulas: [PHPFormula], global: String?) {
        let fm = FileManager.default
        let optDir = "\(Shell.brewPrefix)/opt"
        var byFormula: [String: PHPFormula] = [:]
        let entries = (try? fm.contentsOfDirectory(atPath: optDir)) ?? []
        for entry in entries where entry == "php" || entry.hasPrefix("php@") {
            guard let target = try? fm.destinationOfSymbolicLink(atPath: "\(optDir)/\(entry)") else { continue }
            // ../Cellar/php@8.4/8.4.27_1 → formule « php@8.4 », version « 8.4.27 »
            let parts = target.split(separator: "/")
            guard parts.count >= 2 else { continue }
            let formula = String(parts[parts.count - 2])
            let full = String(parts[parts.count - 1]).split(separator: "_").first.map(String.init) ?? ""
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
        let url = URL(fileURLWithPath: "\(home)/.config/valet/config.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tld = json["tld"] as? String else { return "test" }
        return tld
    }

    // MARK: - Rafraîchissement

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefresh = Date()
        }

        yerdDetected = FileManager.default.isExecutableFile(atPath: "\(Self.home)/.local/bin/yerd")
        let php = Self.scanPHPFormulas()
        phpFormulas = php.formulas
        globalPHP = php.global
        mariadbInstalled = FileManager.default.fileExists(atPath: "\(Shell.brewPrefix)/opt/mariadb")

        async let mariadb = mariadbInstalled ? Self.queryMariaDB() : nil

        if let binary = Self.locateValet() {
            install = .installed(binary: binary)
            tld = Self.readTLD()
            async let status = Shell.run(binary, ["status"])
            async let links = Shell.run(binary, ["links"])
            async let proxiesOut = Shell.run(binary, ["proxies"])
            let (s, l, p) = await (status, links, proxiesOut)
            running = s.succeeded
            sites = Self.parseSites(l.output)
            proxies = Self.parseProxies(p.output)
        } else {
            install = .notInstalled
            running = nil
            sites = []
            proxies = []
        }
        mariadbRunning = await mariadb
    }

    private static func queryMariaDB() async -> Bool? {
        let result = await Shell.run(brew, ["services", "info", "mariadb", "--json"])
        guard result.succeeded,
              let data = result.output.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first else { return nil }
        return first["running"] as? Bool
    }

    // MARK: - Analyse des tableaux de Valet

    /// Valet affiche des tableaux Symfony (`| Site | SSL | URL | … |`). On les lit par nom de colonne.
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

    nonisolated static func parseSites(_ text: String) -> [ValetSite] {
        parseTable(text).compactMap { row in
            guard let name = row["site"], !name.isEmpty else { return nil }
            return ValetSite(
                name: name,
                secured: isSecure(row["ssl"]),
                url: row["url"] ?? "",
                path: row["path"] ?? "",
                php: row["php version"] ?? row["php"] ?? ""
            )
        }
    }

    nonisolated static func parseProxies(_ text: String) -> [ValetProxy] {
        parseTable(text).compactMap { row in
            guard let name = row["site"], !name.isEmpty else { return nil }
            return ValetProxy(name: name, secured: isSecure(row["ssl"]), url: row["url"] ?? "", host: row["host"] ?? "")
        }
    }

    // MARK: - Actions

    private func valet(_ label: String, _ args: [String], cwd: URL? = nil) async {
        guard case let .installed(binary) = install else {
            report(label, CommandResult(status: 1, output: "Valet n'est pas installé."))
            return
        }
        await execute(label) { await Shell.run(binary, args, cwd: cwd, allowSudoPrompt: true) }
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
            lastMessage = "\(label) : OK"
        } else if Self.isSudoFailure(result.output) {
            lastMessage = "\(label) : droits administrateur refusés ou mot de passe annulé. "
                + "Relance l'action, ou lance la commande dans un Terminal."
        } else {
            lastMessage = "\(label) : échec (code \(result.status))"
        }
    }

    private static func isSudoFailure(_ output: String) -> Bool {
        let o = output.lowercased()
        return o.contains("sudo:") && (o.contains("password") || o.contains("askpass") || o.contains("terminal"))
    }

    func start() async { await valet("Démarrage de Valet", ["start"]) }
    func stop() async { await valet("Arrêt de Valet", ["stop"]) }

    func useGlobalPHP(_ formula: String) async {
        await valet("PHP global → \(formula)", ["use", formula])
    }

    func isolate(_ site: ValetSite, formula: String) async {
        await valet("\(site.name) → \(formula)", ["isolate", formula, "--site=\(site.name)"])
    }

    func unisolate(_ site: ValetSite) async {
        await valet("\(site.name) → PHP global", ["unisolate", "--site=\(site.name)"])
    }

    func setSecure(_ site: ValetSite, _ secure: Bool) async {
        await valet(secure ? "HTTPS pour \(site.name)" : "HTTP pour \(site.name)", [secure ? "secure" : "unsecure", site.name])
    }

    func unlink(_ site: ValetSite) async {
        await valet("Unlink \(site.name)", ["unlink", site.name])
    }

    /// Demande un dossier puis lance `valet link <nom>` dedans.
    func chooseAndLinkFolder() async {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Lier"
        panel.message = "Choisis le dossier du site à lier à Valet"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let name = Self.slug(folder.lastPathComponent)
        await valet("Link \(name)", ["link", name], cwd: folder)
    }

    func addProxy(name: String, port: Int, secure: Bool) async {
        let site = Self.slug(name)
        guard !site.isEmpty, (1...65535).contains(port) else {
            report("Proxy", CommandResult(status: 1, output: "Nom ou port invalide."))
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
        await execute(start ? "Démarrage de MariaDB" : "Arrêt de MariaDB") {
            await Shell.run(Self.brew, ["services", start ? "start" : "stop", "mariadb"])
        }
    }

    func open(_ site: ValetSite) {
        if let url = URL(string: displayURL(site)) { NSWorkspace.shared.open(url) }
    }

    func open(_ proxy: ValetProxy) {
        if let url = URL(string: displayURL(proxy)) { NSWorkspace.shared.open(url) }
    }

    func reveal(_ site: ValetSite) {
        guard !site.path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: site.path)])
    }

    /// Nom de site sûr pour Valet : minuscules, chiffres et tirets.
    nonisolated static func slug(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let mapped = lowered.map { $0.isLetter && $0.isASCII || $0.isNumber ? $0 : "-" }
        return String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }
}
