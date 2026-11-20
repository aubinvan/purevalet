import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, sites, proxies, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Général"
        case .sites: return "Sites"
        case .proxies: return "Proxys"
        case .about: return "À propos"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .sites: return "link"
        case .proxies: return "arrow.left.arrow.right"
        case .about: return "info.circle"
        }
    }
}

/// Fenêtre de réglages créée à la demande et libérée à la fermeture (rien ne reste en mémoire).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var selection = TabSelection()

    func show(model: ValetModel, tab: SettingsTab? = nil) {
        if let tab { selection.tab = tab }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = Self.makeWindow(model: model, selection: selection)
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    static func makeWindow(model: ValetModel, selection: TabSelection) -> NSWindow {
        let root = SettingsView(selection: selection).environment(model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Valet Desktop"
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 480)
        window.contentView = NSHostingView(rootView: root)
        return window
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }
}

@Observable
final class TabSelection {
    var tab: SettingsTab = .general
}

// MARK: - Vue principale (barre latérale + détail)

struct SettingsView: View {
    @Environment(ValetModel.self) private var model
    @Bindable var selection: TabSelection

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: Binding(
                get: { selection.tab },
                set: { if let tab = $0 { selection.tab = tab } }
            )) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            detail
                .navigationTitle(selection.tab.title)
                .safeAreaInset(edge: .bottom) { FeedbackBar() }
                .toolbar {
                    ToolbarItem {
                        if model.busyLabel != nil {
                            ProgressView().controlSize(.small)
                        } else {
                            Button {
                                Task { await model.refresh() }
                            } label: {
                                Label("Actualiser", systemImage: "arrow.clockwise")
                            }
                            .help("Actualiser l'état de Valet")
                        }
                    }
                }
        }
        .frame(minWidth: 640, minHeight: 480)
        .task { await model.refresh() }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection.tab {
        case .general: GeneralPane()
        case .sites: SitesPane()
        case .proxies: ProxiesPane()
        case .about: AboutPane()
        }
    }
}

// MARK: - Général

struct GeneralPane: View {
    @Environment(ValetModel.self) private var model

    var body: some View {
        Form {
            Section {
                HStack {
                    Label {
                        Text("État")
                    } icon: {
                        Image(systemName: "power")
                    }
                    Spacer()
                    StatusBadge()
                    if model.isInstalled {
                        if model.running == true {
                            Button("Arrêter") { Task { await model.stop() } }
                        } else {
                            Button("Démarrer") { Task { await model.start() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                if model.isInstalled {
                    LabeledContent {
                        Text(".\(model.tld)").foregroundStyle(.secondary)
                    } label: {
                        Label("Domaine", systemImage: "globe")
                    }
                }
            } header: {
                Text("Valet")
            }

            if model.install == .notInstalled {
                NotInstalledSection()
            }

            if model.isInstalled {
                Section {
                    Picker(selection: Binding(
                        get: { model.globalPHP ?? "" },
                        set: { formula in Task { await model.useGlobalPHP(formula) } }
                    )) {
                        ForEach(model.phpFormulas) { php in
                            Text(php.label).tag(php.formula)
                        }
                    } label: {
                        Label("Version globale", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Text("Équivaut à `valet use`. Un site isolé garde sa propre version (onglet Sites).")
                        .settingsCaption()
                } header: {
                    Text("PHP")
                }
            }

            if model.mariadbInstalled {
                Section {
                    HStack {
                        Label("MariaDB (Homebrew)", systemImage: "cylinder.split.1x2")
                        Spacer()
                        Text(model.mariadbRunning == true ? "Démarré" : (model.mariadbRunning == false ? "Arrêté" : "…"))
                            .foregroundStyle(.secondary)
                        if model.mariadbRunning == true {
                            Button("Arrêter") { Task { await model.setMariaDB(false) } }
                        } else {
                            Button("Démarrer") { Task { await model.setMariaDB(true) } }
                        }
                    }
                    if model.yerdDetected {
                        Text("Yerd a sa propre base de données : une seule peut écouter le port 3306 à la fois.")
                            .settingsCaption()
                    }
                } header: {
                    Text("Base de données")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct StatusBadge: View {
    @Environment(ValetModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(model.statusText).foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch model.install {
        case .notInstalled: return .orange
        case .unknown: return .gray
        case .installed: return model.running == true ? .green : .red
        }
    }
}

struct NotInstalledSection: View {
    @Environment(ValetModel.self) private var model

    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Valet n'est pas installé sur ce Mac").bold()
                    Text("Aucun binaire `valet` trouvé (Composer global ou Homebrew). Valet Desktop n'installe rien lui-même : lance ces commandes dans un Terminal, puis clique sur Actualiser.")
                        .settingsCaption()
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }

            HStack {
                Text("composer global require laravel/valet\nvalet install")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("composer global require laravel/valet && valet install", forType: .string)
                } label: {
                    Label("Copier", systemImage: "doc.on.doc")
                }
            }

            if model.yerdDetected {
                Label {
                    Text("Yerd est présent : il utilise aussi les ports 80/443 et le DNS .test. Arrête-le avant d'installer ou de démarrer Valet.")
                        .settingsCaption()
                } icon: {
                    Image(systemName: "info.circle")
                }
            }
        } header: {
            Text("Installation")
        }
    }
}

// MARK: - Sites

struct SitesPane: View {
    @Environment(ValetModel.self) private var model

    var body: some View {
        if !model.isInstalled {
            NotInstalledPlaceholder()
        } else {
            Form {
                Section {
                    if model.sites.isEmpty {
                        Text("Aucun site lié. Utilise « Lier un dossier… » pour en ajouter un.").settingsCaption()
                    }
                    ForEach(model.sites) { site in
                        SiteRow(site: site)
                    }
                } header: {
                    HStack {
                        Text("Sites liés")
                        Spacer()
                        Button {
                            Task { await model.chooseAndLinkFolder() }
                        } label: {
                            Label("Lier un dossier…", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct SiteRow: View {
    @Environment(ValetModel.self) private var model
    let site: ValetSite

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: site.secured ? "lock.fill" : "lock.open")
                .foregroundStyle(site.secured ? .green : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Button(model.displayURL(site)) { model.open(site) }
                    .buttonStyle(.link)
                Text(site.path)
                    .settingsCaption()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if !site.php.isEmpty {
                Text(site.php).font(.caption).foregroundStyle(.secondary)
            }
            Menu {
                Button(site.secured ? "Passer en HTTP (unsecure)" : "Passer en HTTPS (secure)") {
                    Task { await model.setSecure(site, !site.secured) }
                }
                Menu("Version PHP du site") {
                    ForEach(model.phpFormulas) { php in
                        Button(php.label) { Task { await model.isolate(site, formula: php.formula) } }
                    }
                    Divider()
                    Button("Revenir au PHP global (unisolate)") { Task { await model.unisolate(site) } }
                }
                Button("Afficher dans le Finder") { model.reveal(site) }
                Divider()
                Button("Unlink", role: .destructive) { Task { await model.unlink(site) } }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

// MARK: - Proxys

struct ProxiesPane: View {
    @Environment(ValetModel.self) private var model
    @State private var name = ""
    @State private var port = ""
    @State private var secure = true

    var body: some View {
        if !model.isInstalled {
            NotInstalledPlaceholder()
        } else {
            Form {
                Section {
                    if model.proxies.isEmpty {
                        Text("Aucun proxy.").settingsCaption()
                    }
                    ForEach(model.proxies) { proxy in
                        HStack(spacing: 10) {
                            Image(systemName: proxy.secured ? "lock.fill" : "lock.open")
                                .foregroundStyle(proxy.secured ? .green : .secondary)
                                .frame(width: 16)
                            Button(model.displayURL(proxy)) { model.open(proxy) }
                                .buttonStyle(.link)
                            Text("→ \(proxy.host)").settingsCaption().lineLimit(1)
                            Spacer()
                            Button(role: .destructive) {
                                Task { await model.unproxy(proxy) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("valet unproxy \(proxy.name)")
                        }
                    }
                } header: {
                    Text("Proxys actifs")
                }

                Section {
                    TextField(text: $name, prompt: Text("mon-app")) {
                        Label("Nom", systemImage: "character.cursor.ibeam")
                    }
                    TextField(text: $port, prompt: Text("5173")) {
                        Label("Port local", systemImage: "number")
                    }
                    Toggle(isOn: $secure) {
                        Label("HTTPS", systemImage: "lock")
                    }
                    HStack {
                        Text(preview).settingsCaption()
                        Spacer()
                        Button("Ajouter") {
                            let portNumber = Int(port) ?? 0
                            Task {
                                await model.addProxy(name: name, port: portNumber, secure: secure)
                                if !model.lastFailed {
                                    name = ""
                                    port = ""
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.isEmpty || Int(port) == nil)
                    }
                } header: {
                    Text("Ajouter un proxy (Node, Vite…)")
                }
            }
            .formStyle(.grouped)
        }
    }

    private var preview: String {
        let slug = ValetModel.slug(name.isEmpty ? "mon-app" : name)
        return "\(secure ? "https" : "http")://\(slug).\(model.tld)  →  http://127.0.0.1:\(port.isEmpty ? "5173" : port)"
    }
}

// MARK: - À propos

struct AboutPane: View {
    @Environment(ValetModel.self) private var model

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Valet Desktop").font(.title2.bold())
                        Text("Laravel Valet dans la barre de menus").settingsCaption()
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent {
                    Text(version).foregroundStyle(.secondary)
                } label: {
                    Label("Version", systemImage: "info.circle")
                }
                HStack {
                    Label("Valet Desktop est open source (MIT)", systemImage: "chevron.left.forwardslash.chevron.right")
                    Spacer()
                    Link("Voir sur GitHub", destination: URL(string: "https://github.com/aubinvan/valet-desktop")!)
                }
                HStack {
                    Label("Nouvelles versions", systemImage: "arrow.down.circle")
                    Spacer()
                    Link("Releases", destination: URL(string: "https://github.com/aubinvan/valet-desktop/releases")!)
                }
            }

            Section {
                LabeledContent {
                    Text(model.valetBinary ?? "non installé")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } label: {
                    Label("Binaire Valet", systemImage: "terminal")
                }
                LabeledContent {
                    Text(Shell.brewPrefix).foregroundStyle(.secondary)
                } label: {
                    Label("Homebrew", systemImage: "shippingbox")
                }
            } header: {
                Text("Environnement")
            } footer: {
                Text("Projet communautaire, non affilié à Laravel. Aucune tâche en arrière-plan : l'état est relu à l'ouverture du menu.")
                    .settingsCaption()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Éléments partagés

struct NotInstalledPlaceholder: View {
    var body: some View {
        ContentUnavailableView {
            Label("Valet non installé", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Installe Laravel Valet (voir l'onglet Général), puis actualise.")
        }
    }
}

struct FeedbackBar: View {
    @Environment(ValetModel.self) private var model
    @State private var showDetails = false

    var body: some View {
        if let message = model.lastMessage {
            HStack(spacing: 8) {
                Image(systemName: model.lastFailed ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .foregroundStyle(model.lastFailed ? .red : .green)
                Text(message).font(.callout).lineLimit(2)
                Spacer()
                if !model.lastOutput.isEmpty {
                    Button("Détails") { showDetails.toggle() }
                        .popover(isPresented: $showDetails, arrowEdge: .top) {
                            ScrollView {
                                Text(model.lastOutput)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }
                            .frame(width: 460, height: 240)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}

extension Text {
    /// Texte d'aide en petit et grisé, comme dans les réglages de macOS.
    func settingsCaption() -> some View {
        font(.caption).foregroundStyle(.secondary)
    }
}
