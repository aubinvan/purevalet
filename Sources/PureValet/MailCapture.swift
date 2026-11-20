import Darwin
import Foundation

/// E-mail capture with Mailpit (Homebrew formula `mailpit`): every e-mail sent by a local site lands in
/// a local inbox instead of reaching real people.
///
/// PureValet runs Mailpit itself, as a child process bound to 127.0.0.1 only (the Homebrew service
/// listens on every interface). It stops with "Stop all services" and when PureValet quits.
/// Messages are kept in PureValet's Application Support folder between runs.
@MainActor
final class MailCapture {
    static let shared = MailCapture()

    nonisolated static let smtpPort = 1025
    nonisolated static let webPort = 8025
    nonisolated static var binary: String { "\(Shell.brewPrefix)/opt/mailpit/bin/mailpit" }
    nonisolated static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: binary) }
    nonisolated static var webURL: URL { URL(string: "http://127.0.0.1:\(webPort)")! }

    /// `sendmail_path` for PHP-FPM, so `mail()` (WordPress's default) goes to Mailpit. Nil when Mailpit
    /// is not installed: PHP keeps its default.
    nonisolated static var sendmailPath: String? {
        isInstalled ? sendmailCommand(binary: binary) : nil
    }

    nonisolated static func sendmailCommand(binary: String) -> String {
        "\(binary) sendmail -S 127.0.0.1:\(smtpPort)"
    }

    /// Mailpit's arguments: local-only ports, persistent inbox, any SMTP login accepted (apps configured
    /// with a user name and password for their real SMTP server keep working).
    nonisolated static func arguments(database: String) -> [String] {
        ["--listen", "127.0.0.1:\(webPort)", "--smtp", "127.0.0.1:\(smtpPort)", "--database", database,
         "--smtp-auth-accept-any", "--smtp-auth-allow-insecure"]
    }

    /// `.env` lines for a Laravel project.
    nonisolated static let laravelEnv = """
    MAIL_MAILER=smtp
    MAIL_HOST=127.0.0.1
    MAIL_PORT=\(smtpPort)
    MAIL_USERNAME=null
    MAIL_PASSWORD=null
    MAIL_ENCRYPTION=null
    """

    let dir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PureValet/mailpit", isDirectory: true)
    private var process: Process?

    private func path(_ name: String) -> String { dir.appendingPathComponent(name).path }

    var isRunning: Bool {
        if process?.isRunning == true { return true }
        guard let pid = storedPID else { return false }
        return kill(pid, 0) == 0
    }

    private var storedPID: pid_t? {
        (try? String(contentsOfFile: path("mailpit.pid"), encoding: .utf8))
            .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    func start() async throws {
        guard Self.isInstalled else { throw RootlessError.start(String(localized: "Mailpit is not installed.")) }
        await stop()
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.binary)
        process.arguments = Self.arguments(database: path("mailpit.db"))
        process.currentDirectoryURL = dir
        let logPath = path("mailpit.out")
        fm.createFile(atPath: logPath, contents: nil)
        let log = FileHandle(forWritingAtPath: logPath)
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice
        try process.run()
        self.process = process
        try String(process.processIdentifier).write(toFile: path("mailpit.pid"), atomically: true, encoding: .utf8)

        // Ready when the web UI answers (a port already taken makes Mailpit exit at once).
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        for _ in 0..<30 {
            guard process.isRunning else {
                let output = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
                await stop()
                throw RootlessError.start("Mailpit stopped:\n\(output.suffix(1500))")
            }
            var request = URLRequest(url: Self.webURL, timeoutInterval: 1)
            request.httpMethod = "HEAD"
            if (try? await session.data(for: request)) != nil { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
        await stop()
        throw RootlessError.start(String(localized: "The services did not start in time."))
    }

    func stop() async {
        var pids: [pid_t] = []
        if let process, process.isRunning { pids.append(process.processIdentifier) }
        // Also a Mailpit left by a previous PureValet run, if it really is ours.
        if let pid = storedPID, kill(pid, 0) == 0,
           await Shell.run("/bin/ps", ["-p", String(pid), "-o", "command="]).output.contains(dir.path) {
            pids.append(pid)
        }
        for pid in Set(pids) { kill(pid, SIGTERM) }
        for _ in 0..<30 where pids.contains(where: { kill($0, 0) == 0 }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        for pid in pids where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        process = nil
        try? FileManager.default.removeItem(atPath: path("mailpit.pid"))
    }
}
