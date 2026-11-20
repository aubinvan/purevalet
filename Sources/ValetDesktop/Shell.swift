import Foundation

/// Résultat d'une commande lancée en sous-processus.
struct CommandResult: Sendable {
    let status: Int32
    let output: String

    var succeeded: Bool { status == 0 }
}

/// Lance des commandes externes sans shell intermédiaire.
///
/// Une appli lancée depuis le Finder n'hérite pas du PATH de zsh : on lui fournit
/// un PATH explicite (Homebrew + binaires Composer globaux).
/// Pour `sudo` (que Valet appelle lui-même), on fournit un « askpass » : sudo n'a pas
/// de terminal, il exécute alors ce petit script qui affiche une invite système
/// macOS. Le mot de passe va directement de la boîte de dialogue à sudo, l'appli ne le voit jamais.
enum Shell {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// Préfixe Homebrew : /opt/homebrew (Apple Silicon) ou /usr/local (Intel).
    static let brewPrefix: String = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ? "/opt/homebrew" : "/usr/local"

    static let searchPath: String = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "\(home)/.composer/vendor/bin",
        "\(home)/.config/composer/vendor/bin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ].joined(separator: ":")

    /// Script askpass écrit dans le dossier temporaire au premier besoin.
    static let askpassPath: String = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("valet-desktop-askpass.sh")
        let script = """
        #!/bin/sh
        exec /usr/bin/osascript \\
          -e 'set r to display dialog "Valet a besoin des droits administrateur (sudo).\\n\\nMot de passe macOS :" default answer "" with hidden answer with title "Valet Desktop" with icon caution buttons {"Annuler", "OK"} default button "OK" cancel button "Annuler"' \\
          -e 'text returned of r'
        """
        try? script.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }()

    /// Exécute `executable args…` hors du thread principal et renvoie sa sortie (stdout + stderr).
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
            if let askpass {
                // sudo n'utilise l'askpass sans terminal que si DISPLAY est défini.
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
                return CommandResult(status: -1, output: "Impossible de lancer \(executable) : \(error.localizedDescription)")
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
