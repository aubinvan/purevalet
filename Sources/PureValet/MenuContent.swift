import SwiftUI

/// Menu natif de la barre de menus, sur le modèle de Hex : quelques actions directes,
/// « Réglages… » pour tout le reste, puis « Quitter ».
struct MenuContent: View {
    @Environment(ValetModel.self) private var model

    var body: some View {
        Text(model.statusText)

        if model.isInstalled {
            if model.running == true {
                Button("Arrêter Valet") { Task { await model.stop() } }
            } else {
                Button("Démarrer Valet") { Task { await model.start() } }
            }

            Divider()

            Menu("Sites") {
                if model.sites.isEmpty {
                    Text("Aucun site lié")
                }
                ForEach(model.sites) { site in
                    Button(model.displayURL(site)) { model.open(site) }
                }
                Divider()
                Button("Lier un dossier…") { Task { await model.chooseAndLinkFolder() } }
            }

            Menu("Proxys") {
                if model.proxies.isEmpty {
                    Text("Aucun proxy")
                }
                ForEach(model.proxies) { proxy in
                    Button("\(model.displayURL(proxy))  →  \(proxy.host)") { model.open(proxy) }
                }
                Divider()
                Button("Gérer les proxys…") { SettingsWindowController.shared.show(model: model, tab: .proxies) }
            }

            Menu("PHP global") {
                ForEach(model.phpFormulas) { php in
                    Toggle(php.label, isOn: Binding(
                        get: { php.formula == model.globalPHP },
                        set: { isOn in
                            if isOn { Task { await model.useGlobalPHP(php.formula) } }
                        }
                    ))
                }
            }
        } else if model.install == .notInstalled {
            Button("Comment installer Valet…") { SettingsWindowController.shared.show(model: model, tab: .general) }
        }

        if model.mariadbInstalled {
            Divider()
            if model.mariadbRunning == true {
                Button("Arrêter MariaDB") { Task { await model.setMariaDB(false) } }
            } else {
                Button("Démarrer MariaDB") { Task { await model.setMariaDB(true) } }
            }
        }

        if let message = model.lastMessage {
            Divider()
            Text(message)
        }

        Divider()

        Button("Réglages…") { SettingsWindowController.shared.show(model: model) }
            .keyboardShortcut(",")

        Divider()

        Button("Quitter PureValet") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
