import Foundation

/// Result of a command run as a subprocess.
struct CommandResult: Sendable {
    let status: Int32
    let output: String

    var succeeded: Bool { status == 0 }
}

/// Runs external commands without an intermediate shell.
///
/// An app launched from Finder does not inherit the shell `PATH`, so an explicit one is
/// provided (Homebrew + global Composer binaries).
/// For `sudo` (which Valet calls itself), an askpass helper is provided: with no terminal,
/// sudo runs this small script, which shows a native macOS password dialog. The password goes
/// straight from the dialog to sudo; the app never sees it.
enum Shell {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// Homebrew prefix: /opt/homebrew (Apple Silicon) or /usr/local (Intel).
    static let brewPrefix: String = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ? "/opt/homebrew" : "/usr/local"

    static let searchPath: String = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "\(home)/.composer/vendor/bin",
        "\(home)/.config/composer/vendor/bin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ].joined(separator: ":")

    /// Askpass script written to the temporary folder on first use. Its dialog is localized.
    static let askpassPath: String = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("purevalet-askpass.sh")
        func appleScriptString(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        func shellQuoted(_ text: String) -> String {
            "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        let prompt = String(localized: "Valet needs administrator rights (sudo).\n\nmacOS password:")
        let cancel = String(localized: "Cancel")
        let script = "set r to display dialog \(appleScriptString(prompt)) default answer \"\" with hidden answer "
            + "with title \"PureValet\" with icon caution buttons {\(appleScriptString(cancel)), \"OK\"} "
            + "default button \"OK\" cancel button \(appleScriptString(cancel))"
        let file = """
        #!/bin/sh
        exec /usr/bin/osascript -e \(shellQuoted(script)) -e 'text returned of r'
        """
        try? file.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }()

    /// Runs `executable args…` off the main thread and returns its output (stdout + stderr).
    static func run(_ executable: String, _ arguments: [String], cwd: URL? = nil, allowSudoPrompt: Bool = false) async -> CommandResult {
        let askpass = allowSudoPrompt ? askpassPath : nil
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let cwd { process.currentDirectoryURL = cwd }

            var env = ProcessInfo.processInfo.environment
            env["PATH"] = searchPath
            env["HOME"] = home
            env["NO_COLOR"] = "1"
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            env["HOMEBREW_NO_ENV_HINTS"] = "1"
            env["HOMEBREW_NO_ANALYTICS"] = "1"
            if let askpass {
                // Without a terminal, sudo only uses askpass when DISPLAY is set.
                env["SUDO_ASKPASS"] = askpass
                env["DISPLAY"] = env["DISPLAY"] ?? ":0"
            }
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return CommandResult(status: -1, output: String(localized: "Could not launch \(executable): \(error.localizedDescription)"))
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            return CommandResult(status: process.terminationStatus, output: stripANSI(text))
        }.value
    }

    private static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }
}
