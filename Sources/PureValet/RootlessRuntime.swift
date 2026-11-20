import Darwin
import Foundation

/// "No admin" mode for standard macOS accounts: PureValet runs nginx, PHP-FPM and dnsmasq itself,
/// as the user, with configs generated from Valet's own files (no `sudo`, no root services).
///
/// - nginx listens on all interfaces (macOS lets a standard user bind ports 80/443 only on the
///   wildcard address) and only accepts connections from this Mac (`allow 127.0.0.1/::1; deny all`).
/// - dnsmasq answers `*.<tld>` on 127.0.0.1:1053; `/etc/resolver/<tld>` points there (set once by an admin).
/// - The processes are children of PureValet: quitting PureValet stops them.
@MainActor
final class RootlessRuntime {
    static let shared = RootlessRuntime()
    nonisolated static let dnsPort = 1053

    struct Pool: Equatable {
        let version: String
        let binary: String
        var socket: String { ValetFiles.socketName(version) }
    }

    let dir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PureValet/runtime", isDirectory: true)
    private var children: [String: Process] = [:]
    private var runningPlan: Plan?

    private func path(_ name: String) -> String { dir.appendingPathComponent(name).path }

    // MARK: - State

    var isRunning: Bool {
        guard let nginx = pid("nginx.pid"), alive(nginx), let dns = pid("dnsmasq.pid"), alive(dns) else { return false }
        let pools = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return pools.contains { $0.hasPrefix("php-") && $0.hasSuffix(".pid") && (pid($0).map(alive) ?? false) }
    }

    private func pid(_ file: String) -> pid_t? {
        (try? String(contentsOfFile: path(file), encoding: .utf8))
            .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    /// What to run: the PHP-FPM pools, the global version and the PHP versions replaced because their
    /// Homebrew formula is gone (e.g. `brew upgrade` turned `php` 8.5 into 8.6).
    struct Plan: Equatable {
        var global: String
        var pools: [Pool]
        /// Version asked for (by `valet.sock` or an isolated site) → installed version used instead.
        var substitutions: [String: String] = [:]
        /// `sendmail_path` given to PHP, so `mail()` goes to the mail capture (nil: PHP's default).
        var sendmail: String?
    }

    /// The installed version to use for `wanted`: itself, else the closest newer one (a project made for
    /// 8.5 usually runs on 8.6, and Composer refuses older ones), else the newest older one.
    nonisolated static func closestVersion(to wanted: String, among installed: [String]) -> String? {
        if installed.contains(wanted) { return wanted }
        let sorted = Set(installed).filter { !$0.isEmpty }.sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        return sorted.first { $0.compare(wanted, options: .numeric) == .orderedDescending } ?? sorted.last
    }

    /// PHP-FPM pools needed: the global version plus every version a site is isolated on, each one
    /// replaced by the closest installed version when its formula is gone. Pure, so it can be tested.
    /// - Parameters:
    ///   - requestedGlobal: version `valet.sock` points to (nil: none yet).
    ///   - linked: version of the formula Homebrew links as `php`, used when nothing is requested.
    nonisolated static func plan(requestedGlobal: String?, linked: String?, isolated: Set<String>,
                                 formulas: [PHPFormula], brewPrefix: String = Shell.brewPrefix,
                                 sendmail: String? = nil) -> Plan? {
        let installed = formulas.map(\.version)
        guard let wanted = requestedGlobal ?? linked ?? installed.first,
              let global = closestVersion(to: wanted, among: installed) else { return nil }
        var substitutions: [String: String] = [:]
        if wanted != global { substitutions[wanted] = global }
        var versions: Set<String> = [global]
        for version in isolated {
            guard let used = closestVersion(to: version, among: installed) else { continue }
            if used != version { substitutions[version] = used }
            versions.insert(used)
        }
        let pools = versions.sorted().compactMap { version -> Pool? in
            guard let formula = formulas.first(where: { $0.version == version }) else { return nil }
            return Pool(version: version, binary: "\(brewPrefix)/opt/\(formula.formula)/sbin/php-fpm")
        }
        return Plan(global: global, pools: pools, substitutions: substitutions, sendmail: sendmail)
    }

    func plan(files: ValetFiles, requestedGlobal: String?, linked: String?, formulas: [PHPFormula]) -> Plan? {
        Self.plan(requestedGlobal: requestedGlobal, linked: linked, isolated: files.isolatedVersions(),
                  formulas: formulas, sendmail: MailCapture.sendmailPath)
    }

    // MARK: - Config generation

    /// Valet's site config, made usable without root: wildcard listens and a user-writable error log.
    nonisolated static func rootless(_ conf: String, errorLog: String) -> String {
        var text = conf.replacingOccurrences(of: #"(?<!#)listen 127\.0\.0\.1:(\d+)"#, with: "listen $1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<!#)listen \[::1\]:(\d+)"#, with: "listen [::]:$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"error_log "[^"]*";"#, with: "error_log \"\(errorLog)\";", options: .regularExpression)
        return text
    }

    func generate(files: ValetFiles, plan: Plan) throws {
        let fm = FileManager.default
        let sites = dir.appendingPathComponent("sites")
        try? fm.removeItem(at: sites)
        try fm.createDirectory(at: sites, withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("tmp"), withIntermediateDirectories: true)
        let errorLog = path("nginx-error.log")

        for name in ["mime.types", "fastcgi_params"] {
            let target = path(name)
            try? fm.removeItem(atPath: target)
            try fm.copyItem(atPath: "\(Shell.brewPrefix)/etc/nginx/\(name)", toPath: target)
        }
        for file in (try? fm.contentsOfDirectory(atPath: files.nginxDir)) ?? [] where !file.hasPrefix(".") {
            guard var conf = try? String(contentsOfFile: "\(files.nginxDir)/\(file)", encoding: .utf8) else { continue }
            // A site isolated on a PHP that is gone uses the replacement version (in this copy only:
            // Valet's own file keeps the version the user chose).
            if let isolated = ValetFiles.isolatedVersion(conf)?.replacingOccurrences(of: "php@", with: ""),
               let used = plan.substitutions[isolated] {
                conf = ValetFiles.withSocket(conf, version: "php@\(used)")
            }
            try Self.rootless(conf, errorLog: errorLog)
                .write(to: sites.appendingPathComponent("\(file).conf"), atomically: true, encoding: .utf8)
        }
        try Self.rootless(files.render(try files.stub("valet.conf")), errorLog: errorLog)
            .write(toFile: path("valet.conf"), atomically: true, encoding: .utf8)

        let tmp = path("tmp")
        let nginx = """
        worker_processes 2;
        pid "\(path("nginx.pid"))";
        error_log "\(errorLog)";
        events { worker_connections 1024; }
        http {
            include mime.types;
            default_type application/octet-stream;
            sendfile on;
            keepalive_timeout 65;
            types_hash_max_size 2048;
            fastcgi_read_timeout 1800;
            client_max_body_size 512M;
            server_names_hash_bucket_size 128;
            gzip on;
            client_body_temp_path "\(tmp)/body";
            proxy_temp_path "\(tmp)/proxy";
            fastcgi_temp_path "\(tmp)/fastcgi";
            uwsgi_temp_path "\(tmp)/uwsgi";
            scgi_temp_path "\(tmp)/scgi";
            access_log off;
            # Without root, nginx must listen on all interfaces: only this Mac may connect.
            allow 127.0.0.1;
            allow ::1;
            deny all;
            include "\(sites.path)/*.conf";
            include "\(path("valet.conf"))";
        }

        """
        try nginx.write(toFile: path("nginx.conf"), atomically: true, encoding: .utf8)

        for pool in plan.pools {
            let mail = plan.sendmail.map { "php_admin_value[sendmail_path] = \($0)\n" } ?? ""
            let fpm = """
            [global]
            pid = \(path("php-\(pool.version).pid"))
            error_log = \(path("php-\(pool.version).log"))
            daemonize = no

            [valet]
            listen = \(files.home)/\(pool.socket)
            listen.mode = 0777
            pm = dynamic
            pm.max_children = 5
            pm.start_servers = 1
            pm.min_spare_servers = 1
            pm.max_spare_servers = 2
            env['LC_ALL'] = C
            env['PGGSSENCMODE'] = disable
            \(mail)
            """
            try fpm.write(toFile: path("php-\(pool.version).conf"), atomically: true, encoding: .utf8)
        }

        let dns = """
        port=\(Self.dnsPort)
        listen-address=127.0.0.1
        bind-interfaces
        pid-file=\(path("dnsmasq.pid"))
        conf-dir=\(files.home)/dnsmasq.d/,*.conf
        address=/\(files.tld)/127.0.0.1
        address=/\(files.tld)/::1
        local=/\(files.tld)/

        """
        try dns.write(toFile: path("dnsmasq.conf"), atomically: true, encoding: .utf8)

        // `valet.sock` (used by non-isolated sites) points at the global version's pool.
        // If the global PHP was replaced, this also repairs the link for the `valet` CLI.
        let link = "\(files.home)/valet.sock"
        let target = "\(files.home)/\(ValetFiles.socketName(plan.global))"
        if (try? fm.destinationOfSymbolicLink(atPath: link)) != target {
            try? fm.removeItem(atPath: link)
            try fm.createSymbolicLink(atPath: link, withDestinationPath: target)
        }
    }

    // MARK: - Processes

    func start(files: ValetFiles, plan: Plan) async throws {
        await stop()
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let pools = plan.pools
        guard !pools.isEmpty else { throw RootlessError.start(String(localized: "No Homebrew PHP found for the global version.")) }
        try generate(files: files, plan: plan)

        for pool in pools {
            try? fm.removeItem(atPath: "\(files.home)/\(pool.socket)")
            try spawn("php-\(pool.version)", pool.binary, ["-F", "-y", path("php-\(pool.version).conf")])
        }
        try spawn("nginx", "\(Shell.brewPrefix)/opt/nginx/bin/nginx", ["-c", path("nginx.conf"), "-g", "daemon off;"])
        try spawn("dnsmasq", "\(Shell.brewPrefix)/opt/dnsmasq/sbin/dnsmasq", ["-k", "-C", path("dnsmasq.conf")])
        runningPlan = plan

        for _ in 0..<40 {
            if let failed = children.first(where: { !$0.value.isRunning }) {
                let log = (try? String(contentsOfFile: path("\(failed.key).out"), encoding: .utf8)) ?? ""
                await stop()
                throw RootlessError.start("\(failed.key) stopped:\n\(log.suffix(1500))")
            }
            let socketsReady = pools.allSatisfy { fm.fileExists(atPath: "\(files.home)/\($0.socket)") }
            if socketsReady && pid("nginx.pid") != nil && pid("dnsmasq.pid") != nil { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
        await stop()
        throw RootlessError.start(String(localized: "The services did not start in time."))
    }

    /// Applies site changes: regenerates the configs, restarts PHP pools if they changed, reloads nginx.
    func reload(files: ValetFiles, plan: Plan) async throws {
        guard isRunning else { return }
        if plan.pools != runningPlan?.pools || plan.sendmail != runningPlan?.sendmail {
            try await start(files: files, plan: plan)
            return
        }
        try generate(files: files, plan: plan)
        runningPlan = plan
        if let nginx = pid("nginx.pid") { kill(nginx, SIGHUP) }
    }

    func stop() async {
        var pids = children.values.filter(\.isRunning).map(\.processIdentifier)
        // Also processes left by a previous PureValet run (found through their pid files).
        for file in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where file.hasSuffix(".pid") {
            if let pid = pid(file), alive(pid), await ownsProcess(pid) { pids.append(pid) }
        }
        for pid in Set(pids) { kill(pid, SIGTERM) }
        for _ in 0..<30 where pids.contains(where: alive) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        for pid in pids where alive(pid) { kill(pid, SIGKILL) }
        children = [:]
        runningPlan = nil
        for file in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where file.hasSuffix(".pid") {
            try? FileManager.default.removeItem(atPath: path(file))
        }
    }

    /// Only stop processes that really run one of our configs.
    private func ownsProcess(_ pid: pid_t) async -> Bool {
        let result = await Shell.run("/bin/ps", ["-p", String(pid), "-o", "command="])
        return result.output.contains(dir.path)
    }

    private func spawn(_ key: String, _ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Shell.searchPath
        process.environment = env
        let logPath = path("\(key).out")
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let log = FileHandle(forWritingAtPath: logPath)
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice
        try process.run()
        children[key] = process
    }
}

/// One-time setup that needs an administrator account (asked through the standard macOS dialog):
/// remove Valet's root services, point `/etc/resolver/<tld>` at the rootless DNS, trust Valet's CA.
enum RootlessSetup {
    struct Status: Equatable {
        var resolverReady = false
        var rootServices: [String] = []
        var caTrusted = true
        /// Root nginx / PHP-FPM / dnsmasq left running by Valet's former services.
        var leftoverRootProcesses = false

        /// What rootless mode really needs: the DNS pointing at PureValet and Valet's CA trusted.
        /// Leftover root services are harmless once the DNS bypasses them: they are reported, never required,
        /// so nobody is pushed to use an administrator account for them.
        var ready: Bool { resolverReady && caTrusted }
        var hasLeftovers: Bool { !rootServices.isEmpty || leftoverRootProcesses }
    }

    static func status(files: ValetFiles, formulas: [PHPFormula]) async -> Status {
        var status = Status()
        let resolver = (try? String(contentsOfFile: "/etc/resolver/\(files.tld)", encoding: .utf8)) ?? ""
        status.resolverReady = resolver.contains("port \(RootlessRuntime.dnsPort)")
        for label in serviceLabels(formulas: formulas) {
            let loaded = await Shell.run("/bin/launchctl", ["print", "system/\(label)"]).succeeded
            if loaded || FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/\(label).plist") {
                status.rootServices.append(label)
            }
        }
        let processes = await Shell.run("/bin/ps", ["-axo", "user=,command="]).output
        status.leftoverRootProcesses = leftoverPatterns.contains { pattern in
            processes.split(separator: "\n").contains { $0.contains(pattern) }
        }
        if FileManager.default.fileExists(atPath: files.caPem) {
            status.caTrusted = await Shell.run("/usr/bin/security", ["verify-cert", "-c", files.caPem]).succeeded
        }
        return status
    }

    /// Command lines of Valet's root services (PureValet's own processes use its runtime folder instead).
    nonisolated static let leftoverPatterns = [
        "dnsmasq --keep-in-foreground -C \(Shell.brewPrefix)/etc/dnsmasq.conf",
        "nginx: master process \(Shell.brewPrefix)/opt/nginx/bin/nginx -g daemon off;",
        "php-fpm: master process (\(Shell.brewPrefix)/etc/php/",
    ]

    /// Root launchd services of Valet's formulae, under both Homebrew naming schemes
    /// (`homebrew.mxcl.*` before Homebrew 5, `sh.brew.*` after).
    static func serviceLabels(formulas: [PHPFormula]) -> [String] {
        let names = ["nginx", "dnsmasq"] + formulas.map(\.formula)
        return names.flatMap { ["homebrew.mxcl.\($0)", "sh.brew.\($0)"] }
    }

    /// `pkill -f` takes an extended regular expression: escape the special characters of a literal.
    nonisolated static func regexEscaped(_ text: String) -> String {
        var out = ""
        for c in text {
            if "\\^$.|?*+()[]{}".contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }

    /// Names of this Mac's administrator accounts (shown so the user knows which one to type).
    static func adminAccounts() async -> [String] {
        let out = await Shell.run("/usr/bin/dscl", [".", "-read", "/Groups/admin", "GroupMembership"]).output
        return out.replacingOccurrences(of: "GroupMembership:", with: "")
            .split(separator: " ").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "root" && !$0.hasPrefix("_") }
    }

    /// Turns an `osascript` failure into a clear explanation.
    nonisolated static func explain(_ result: CommandResult) -> CommandResult {
        guard !result.succeeded else { return result }
        let o = result.output
        let message: String
        if o.contains("-128") {
            message = String(localized: "Setup cancelled.")
        } else if o.contains("-60007") || o.contains("-60005") || o.lowercased().contains("password") {
            message = String(localized: "The administrator name or password was refused. Type the name of an administrator account (not your standard account) and its password.")
        } else {
            message = o
        }
        return CommandResult(status: result.status, output: message + "\n\n" + o)
    }

    /// The shell script run once as root. Pure, so it can be tested and reviewed.
    nonisolated static func script(user: String, home: String, tld: String, labels: [String], caPem: String) -> String {
        func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let services = labels.map(quoted).joined(separator: " ")
        return """
        for l in \(services); do launchctl bootout system/"$l" 2>/dev/null; rm -f /Library/LaunchDaemons/"$l".plist; done
        \(leftoverPatterns.map { "pkill -f \(quoted(regexEscaped($0))) 2>/dev/null" }.joined(separator: "\n"))
        mkdir -p /etc/resolver
        printf 'nameserver 127.0.0.1\\nport \(RootlessRuntime.dnsPort)\\n' > /etc/resolver/\(quoted(tld))
        chown -R \(quoted(user)):staff \(quoted("\(home)/.config/valet"))
        if [ -f \(quoted(caPem)) ]; then security verify-cert -c \(quoted(caPem)) >/dev/null 2>&1 || security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \(quoted(caPem)); fi
        exit 0
        """
    }

    /// Runs the script through `do shell script … with administrator privileges`: macOS asks for an
    /// administrator name and password (works from a standard account).
    static func run(files: ValetFiles, formulas: [PHPFormula]) async -> CommandResult {
        let script = script(user: NSUserName(), home: Shell.home, tld: files.tld,
                            labels: serviceLabels(formulas: formulas), caPem: files.caPem)
        func appleScriptString(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let prompt = String(localized: "PureValet needs an administrator account once. Replace the name with an administrator account (not your standard account) and type its password.")
        let apple = "do shell script \(appleScriptString(script)) with prompt \(appleScriptString(prompt)) with administrator privileges"
        return explain(await Shell.run("/usr/bin/osascript", ["-e", apple]))
    }
}
