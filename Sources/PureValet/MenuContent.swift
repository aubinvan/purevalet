import SwiftUI

/// Native menu bar menu, Hex-style: a few direct actions, "Settings…" for the rest, then "Quit".
struct MenuContent: View {
    @Environment(ValetModel.self) private var model

    var body: some View {
        Button {
            SettingsWindowController.shared.show(model: model, tab: .general)
        } label: {
            Label {
                Text(model.statusText)
            } icon: {
                Image(nsImage: StatusDot.image(model.valetDot))
            }
        }

        if model.isInstalled && model.rootless && !model.rootlessSetup.ready {
            Button("Finish Setup (Admin, Once)…") { Task { await model.runRootlessSetup() } }
            Divider()
        }

        if model.isInstalled || model.mariadbInstalled {
            if model.anyServiceStopped {
                Button("Start All Services") { Task { await model.startAll() } }
            }
            if model.anyServiceRunning {
                Button("Stop All Services") { Task { await model.stopAll() } }
            }
            Divider()
        }

        if model.isInstalled {
            if model.running == true {
                Button("Restart Valet") { Task { await model.restart() } }
                Button("Stop Valet") { Task { await model.stop() } }
            } else {
                Button("Start Valet") { Task { await model.start() } }
            }

            Divider()

            Menu("Sites") {
                if model.sites.isEmpty {
                    Text("No sites")
                }
                ForEach(model.sites) { site in
                    Button {
                        model.open(site)
                    } label: {
                        Label {
                            Text(verbatim: model.displayURL(site))
                        } icon: {
                            Image(nsImage: StatusDot.image(model.dot(for: site)))
                        }
                    }
                }
                Divider()
                Button("Link a Folder…") { Task { await model.chooseAndLinkFolder() } }
                Button("Park a Folder…") { Task { await model.chooseAndParkFolder() } }
            }

            Menu("Proxies") {
                if model.proxies.isEmpty {
                    Text("No proxies")
                }
                ForEach(model.proxies) { proxy in
                    Button(model.displayURL(proxy) + "  →  " + proxy.host) { model.open(proxy) }
                }
                Divider()
                Button("Manage Proxies…") { SettingsWindowController.shared.show(model: model, tab: .proxies) }
            }

            Menu("Global PHP") {
                ForEach(model.phpFormulas) { php in
                    Toggle(php.label, isOn: Binding(
                        get: { php.formula == model.globalPHP },
                        set: { isOn in
                            if isOn { Task { await model.useGlobalPHP(php.formula) } }
                        }
                    ))
                }
            }

            Menu("Logs & Files") {
                Button("Open Logs Folder") { model.openLogs() }
                Button("Open Valet Configuration") { model.openConfig() }
            }
        } else if model.install == .notInstalled {
            Button("How to Install Valet…") { SettingsWindowController.shared.show(model: model, tab: .general) }
        }

        if model.mariadbInstalled {
            Divider()
            if model.mariadbRunning == true {
                Button("Stop MariaDB") { Task { await model.setMariaDB(false) } }
            } else {
                Button("Start MariaDB") { Task { await model.setMariaDB(true) } }
            }
            if model.phpMyAdminAvailable {
                Button("Open phpMyAdmin") { model.openPhpMyAdmin() }
            } else if model.isInstalled {
                Button("Install phpMyAdmin…") { Task { await model.installPhpMyAdmin() } }
            }
        }

        if let message = model.lastMessage {
            Divider()
            Text(message)
        }

        Divider()

        if let update = Updater.shared.available {
            Button("Download PureValet \(update.version)…") { Updater.shared.download(update) }
        }

        Button("Settings…") { SettingsWindowController.shared.show(model: model) }
            .keyboardShortcut(",")

        Divider()

        Button("Quit PureValet") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
