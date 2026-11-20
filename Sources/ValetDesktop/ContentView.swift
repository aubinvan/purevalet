import SwiftUI

struct ContentView: View {
    @Environment(ValetModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if model.isInstalled {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        PHPSection()
                        SitesSection()
                        ProxiesSection()
                    }
                }
                .frame(maxHeight: 420)
            } else if model.install == .notInstalled {
                NotInstalledView()
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            if model.mariadbInstalled {
                Divider()
                MariaDBSection()
            }
            FeedbackView()
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 380)
        .task { await model.refresh() }
        .disabled(model.busyLabel != nil)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text("Laravel Valet").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isInstalled {
                if model.running == true {
                    Button("Stop") { Task { await model.stop() } }
                } else {
                    Button("Start") { Task { await model.start() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var statusText: String {
        if let busy = model.busyLabel { return "\(busy)…" }
        switch model.install {
        case .unknown: return "Vérification…"
        case .notInstalled: return "Valet non installé"
        case .installed:
            switch model.running {
            case .some(true): return "Démarré — .\(model.tld)"
            case .some(false): return "Arrêté"
            case .none: return "État inconnu"
            }
        }
    }

    private var statusColor: Color {
        switch model.install {
        case .notInstalled: return .orange
        case .unknown: return .gray
        case .installed: return model.running == true ? .green : .red
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await model.refresh() }
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            Spacer()
            Button("Quitter") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

// MARK: - Valet absent

struct NotInstalledView: View {
    @Environment(ValetModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Valet n'est pas installé sur ce Mac", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline.bold())
            Text("Aucun binaire `valet` trouvé dans ~/.composer/vendor/bin, ~/.config/composer/vendor/bin ni Homebrew. L'appli n'installe rien elle-même.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Installation manuelle (dans un Terminal) :")
                .font(.caption)
            Text("composer global require laravel/valet\nvalet install")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            if model.yerdDetected {
                Label("Yerd détecté : il utilise aussi les ports 80/443 et le DNS .test. Arrête-le avant d'installer ou de démarrer Valet.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - PHP global

struct PHPSection: View {
    @Environment(ValetModel.self) private var model
    @State private var selection = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("PHP global", systemImage: "chevron.left.forwardslash.chevron.right")
            if model.phpFormulas.isEmpty {
                Text("Aucune formule PHP Homebrew trouvée.").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Picker("", selection: $selection) {
                        ForEach(model.phpFormulas) { php in
                            Text(php.label + (php.formula == model.globalPHP ? "  ✓" : "")).tag(php.formula)
                        }
                    }
                    .labelsHidden()
                    Button("Utiliser") { Task { await model.useGlobalPHP(selection) } }
                        .disabled(selection.isEmpty || selection == model.globalPHP)
                }
            }
        }
        .onAppear { selection = model.globalPHP ?? model.phpFormulas.first?.formula ?? "" }
        .onChange(of: model.globalPHP) { _, new in selection = new ?? selection }
    }
}

// MARK: - Sites

struct SitesSection: View {
    @Environment(ValetModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle("Sites liés", systemImage: "link")
                Spacer()
                Button {
                    Task { await model.chooseAndLinkFolder() }
                } label: {
                    Label("Lier un dossier…", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            if model.sites.isEmpty {
                Text("Aucun site lié (`valet links`).").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.sites) { site in
                SiteRow(site: site)
            }
        }
    }
}

struct SiteRow: View {
    @Environment(ValetModel.self) private var model
    let site: ValetSite

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: site.secured ? "lock.fill" : "lock.open")
                .foregroundStyle(site.secured ? .green : .secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Button(site.url.isEmpty ? "\(site.name).\(model.tld)" : site.url) { model.open(site) }
                    .buttonStyle(.link)
                    .lineLimit(1)
                if !site.php.isEmpty {
                    Text(site.php).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
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

struct ProxiesSection: View {
    @Environment(ValetModel.self) private var model
    @State private var name = ""
    @State private var port = ""
    @State private var secure = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Proxys (Node, Vite…)", systemImage: "arrow.left.arrow.right")
            ForEach(model.proxies) { proxy in
                HStack {
                    Image(systemName: proxy.secured ? "lock.fill" : "lock.open")
                        .foregroundStyle(proxy.secured ? .green : .secondary)
                        .frame(width: 14)
                    Button(proxy.url.isEmpty ? "\(proxy.name).\(model.tld)" : proxy.url) { model.open(proxy) }
                        .buttonStyle(.link)
                        .lineLimit(1)
                    Text("→ \(proxy.host)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button {
                        Task { await model.unproxy(proxy) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("valet unproxy \(proxy.name)")
                }
            }
            HStack {
                TextField("nom", text: $name).frame(width: 110)
                TextField("port", text: $port).frame(width: 60)
                Toggle("HTTPS", isOn: $secure).toggleStyle(.checkbox)
                Spacer()
                Button("Ajouter") {
                    let p = Int(port) ?? 0
                    Task {
                        await model.addProxy(name: name, port: p, secure: secure)
                        if !model.lastFailed { name = ""; port = "" }
                    }
                }
                .disabled(name.isEmpty || Int(port) == nil)
            }
            .textFieldStyle(.roundedBorder)
            .font(.caption)
        }
    }
}

// MARK: - MariaDB

struct MariaDBSection: View {
    @Environment(ValetModel.self) private var model

    var body: some View {
        HStack {
            Image(systemName: "cylinder.split.1x2")
            Text("MariaDB (Homebrew)").font(.subheadline)
            Text(stateText).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if model.mariadbRunning == true {
                Button("Stop") { Task { await model.setMariaDB(false) } }
            } else {
                Button("Start") { Task { await model.setMariaDB(true) } }
            }
        }
    }

    private var stateText: String {
        switch model.mariadbRunning {
        case .some(true): return "démarré"
        case .some(false): return "arrêté"
        case .none: return "…"
        }
    }
}

// MARK: - Retour des commandes

struct FeedbackView: View {
    @Environment(ValetModel.self) private var model
    @State private var showDetails = false

    var body: some View {
        if let message = model.lastMessage {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Image(systemName: model.lastFailed ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .foregroundStyle(model.lastFailed ? .red : .green)
                    Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if !model.lastOutput.isEmpty {
                        Button(showDetails ? "Masquer" : "Détails") { showDetails.toggle() }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
                if showDetails {
                    ScrollView {
                        Text(model.lastOutput)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }
}

struct SectionTitle: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
    }
}
