import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, sites, proxies, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .sites: return String(localized: "Sites")
        case .proxies: return String(localized: "Proxies")
        case .about: return String(localized: "About")
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

/// Settings window, created on demand and released when closed (nothing stays in memory).
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
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PureValet"
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

// MARK: - Main view (sidebar + detail)

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
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .help("Refresh Valet status")
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

// MARK: - General

struct GeneralPane: View {
    @Environment(ValetModel.self) private var model
    @AppStorage(Preferences.startOnLaunchKey) private var startOnLaunch = false
    @AppStorage(Preferences.stopOnQuitKey) private var stopOnQuit = true

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Status", systemImage: "power")
                    Spacer()
                    StatusBadge()
                    if model.isInstalled {
                        if model.running == true {
                            Button("Restart") { Task { await model.restart() } }
                            Button("Stop") { Task { await model.stop() } }
                        } else {
                            Button("Start") { Task { await model.start() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                if model.isInstalled {
                    LabeledContent {
                        Text(model.valetVersion ?? "—").foregroundStyle(.secondary)
                    } label: {
                        Label("Valet CLI version", systemImage: "terminal")
                    }
                    LabeledContent {
                        Text(verbatim: ".\(model.tld)").foregroundStyle(.secondary)
                    } label: {
                        Label("Domain", systemImage: "globe")
                    }
                    HStack {
                        Label("Files", systemImage: "folder")
                        Spacer()
                        Button("Logs") { model.openLogs() }
                        Button("Configuration") { model.openConfig() }
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
                        Label("Global version", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Text("Same as `valet use`. An isolated site keeps its own version (Sites tab).")
                        .settingsCaption()
                } header: {
                    Text("PHP")
                }

                Section {
                    HStack {
                        Label("Password-free commands", systemImage: "key")
                        Spacer()
                        if model.trusted {
                            Text("Enabled").foregroundStyle(.secondary)
                        } else {
                            Button("Enable…") { Task { await model.trust() } }
                        }
                    }
                    Text("Runs `valet trust` once: adds sudoers rules for `valet` and `brew` so Start, Stop and Secure no longer ask for your password.")
                        .settingsCaption()
                } header: {
                    Text("Administrator password")
                }
            }

            if model.mariadbInstalled {
                Section {
                    HStack {
                        Label("MariaDB (Homebrew)", systemImage: "cylinder.split.1x2")
                        Spacer()
                        Text(mariadbState).foregroundStyle(.secondary)
                        if model.mariadbRunning == true {
                            Button("Stop") { Task { await model.setMariaDB(false) } }
                        } else {
                            Button("Start") { Task { await model.setMariaDB(true) } }
                        }
                    }
                    if model.isInstalled {
                        PhpMyAdminRow()
                    }
                } header: {
                    Text("Database")
                }
            }

            Section {
                Toggle(isOn: $startOnLaunch) {
                    Label("Start services when PureValet opens", systemImage: "play.circle")
                }
                Toggle(isOn: $stopOnQuit) {
                    Label("Stop all services when quitting", systemImage: "stop.circle")
                }
                Text("Services are Valet (nginx, PHP-FPM, dnsmasq) and Homebrew MariaDB. When PureValet quits, they are stopped and unregistered, so nothing keeps running or restarts at boot. Enable password-free commands to quit without a password prompt.")
                    .settingsCaption()
                Toggle(isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )) {
                    Label("Open at login", systemImage: "arrow.right.circle")
                }
            } header: {
                Text("App")
            }
        }
        .formStyle(.grouped)
    }

    private var mariadbState: String {
        switch model.mariadbRunning {
        case .some(true): return String(localized: "Running")
        case .some(false): return String(localized: "Stopped")
        case .none: return "…"
        }
    }
}

struct PhpMyAdminRow: View {
    @Environment(ValetModel.self) private var model

    var body: some View {
        HStack {
            Label("phpMyAdmin", systemImage: "tablecells")
            Spacer()
            if let version = model.phpMyAdminVersion {
                Text(verbatim: version).foregroundStyle(.secondary)
                if model.phpMyAdminUpdateAvailable, let latest = model.phpMyAdminLatest?.version {
                    Button("Update to \(latest)") { Task { await model.installPhpMyAdmin() } }
                }
                Button("Open") { model.openPhpMyAdmin() }
                    .buttonStyle(.borderedProminent)
            } else {
                if model.phpMyAdminSite != nil {
                    Button("Open") { model.openPhpMyAdmin() }
                }
                Button(model.phpMyAdminSite == nil ? LocalizedStringKey("Install…") : LocalizedStringKey("Install PureValet's copy…")) {
                    Task { await model.installPhpMyAdmin() }
                }
            }
        }
        .task { await model.fetchPhpMyAdminLatest() }
        Text("Log in with your macOS user name (\(NSUserName())) and an empty password: MariaDB recognises your account through its local socket, so no password is stored. PureValet installs the official release (SHA-256 checked) in its Application Support folder and serves it on `phpmyadmin.\(model.tld)`.")
            .settingsCaption()
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
                    Text("Valet is not installed on this Mac").bold()
                    Text("No `valet` binary found (global Composer or Homebrew). PureValet never installs anything itself: run these commands in Terminal, then click Refresh.")
                        .settingsCaption()
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }

            HStack {
                Text(verbatim: "composer global require laravel/valet\nvalet install")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("composer global require laravel/valet && valet install", forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }

            if model.yerdDetected {
                Label {
                    Text("Yerd is installed: it also uses ports 80/443 and the .test DNS. Stop it before installing or starting Valet.")
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
                        Text("No sites yet. Link a folder, or park a folder that contains your projects.").settingsCaption()
                    }
                    ForEach(model.sites) { site in
                        SiteRow(site: site)
                    }
                } header: {
                    HStack {
                        Text("Sites")
                        Spacer()
                        Button {
                            Task { await model.chooseAndLinkFolder() }
                        } label: {
                            Label("Link a Folder…", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Section {
                    if model.parkedPaths.isEmpty {
                        Text("No parked folders. Every subfolder of a parked folder is served as `folder-name.\(model.tld)`.")
                            .settingsCaption()
                    }
                    ForEach(model.parkedPaths, id: \.self) { path in
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(verbatim: path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                model.reveal(path)
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .buttonStyle(.borderless)
                            .help("Show in Finder")
                            Button(role: .destructive) {
                                Task { await model.forget(path) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Stop serving this folder (valet forget)")
                        }
                    }
                } header: {
                    HStack {
                        Text("Parked folders")
                        Spacer()
                        Button {
                            Task { await model.chooseAndParkFolder() }
                        } label: {
                            Label("Park a Folder…", systemImage: "plus")
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

    private var healthHelp: String {
        switch model.dot(for: site) {
        case .ok: return String(localized: "The site responds")
        case .down: return String(localized: "The site returns an error or does not respond")
        case .unknown: return String(localized: "Not checked yet")
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: StatusDot.image(model.dot(for: site)))
                .help(healthHelp)
            Image(systemName: site.secured ? "lock.fill" : "lock.open")
                .foregroundStyle(site.secured ? .green : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Button(model.displayURL(site)) { model.open(site) }
                    .buttonStyle(.link)
                Text(verbatim: site.path)
                    .settingsCaption()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if site.parked {
                Text("parked").font(.caption).foregroundStyle(.tertiary)
            }
            if !site.php.isEmpty {
                Text(verbatim: site.php).font(.caption).foregroundStyle(.secondary)
            }
            Menu {
                Button(site.secured ? LocalizedStringKey("Switch to HTTP (unsecure)") : LocalizedStringKey("Switch to HTTPS (secure)")) {
                    Task { await model.setSecure(site, !site.secured) }
                }
                Menu("Site PHP Version") {
                    ForEach(model.phpFormulas) { php in
                        Button(php.label) { Task { await model.isolate(site, formula: php.formula) } }
                    }
                    Divider()
                    Button("Use Global PHP (unisolate)") { Task { await model.unisolate(site) } }
                }
                Divider()
                Button("Copy URL") { model.copyURL(site) }
                Button("Show in Finder") { model.reveal(site.path) }
                Button("Open in Terminal") { model.openInTerminal(site.path) }
                if !site.parked {
                    Divider()
                    Button("Unlink", role: .destructive) { Task { await model.unlink(site) } }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

// MARK: - Proxies

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
                        Text("No proxies.").settingsCaption()
                    }
                    ForEach(model.proxies) { proxy in
                        HStack(spacing: 10) {
                            Image(systemName: proxy.secured ? "lock.fill" : "lock.open")
                                .foregroundStyle(proxy.secured ? .green : .secondary)
                                .frame(width: 16)
                            Button(model.displayURL(proxy)) { model.open(proxy) }
                                .buttonStyle(.link)
                            Text(verbatim: "→ \(proxy.host)").settingsCaption().lineLimit(1)
                            Spacer()
                            Button(role: .destructive) {
                                Task { await model.unproxy(proxy) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this proxy (valet unproxy)")
                        }
                    }
                } header: {
                    Text("Active proxies")
                }

                Section {
                    TextField(text: $name, prompt: Text(verbatim: "my-app")) {
                        Label("Name", systemImage: "character.cursor.ibeam")
                    }
                    TextField(text: $port, prompt: Text(verbatim: "5173")) {
                        Label("Local port", systemImage: "number")
                    }
                    Toggle(isOn: $secure) {
                        Label("HTTPS", systemImage: "lock")
                    }
                    HStack {
                        Text(verbatim: preview).settingsCaption()
                        Spacer()
                        Button("Add") {
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
                    Text("Add a proxy (Node, Vite…)")
                }
            }
            .formStyle(.grouped)
        }
    }

    private var preview: String {
        let slug = ValetModel.slug(name.isEmpty ? "my-app" : name)
        return "\(secure ? "https" : "http")://\(slug).\(model.tld)  →  http://127.0.0.1:\(port.isEmpty ? "5173" : port)"
    }
}

// MARK: - About

struct AboutPane: View {
    @Environment(ValetModel.self) private var model

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "PureValet").font(.title2.bold())
                        Text("Laravel Valet in your menu bar").settingsCaption()
                    }
                }
                .padding(.vertical, 4)
                HStack {
                    Label("Open source (MIT)", systemImage: "chevron.left.forwardslash.chevron.right")
                    Spacer()
                    Link("View on GitHub", destination: URL(string: "https://github.com/aubinvan/purevalet")!)
                }
            }

            UpdatesSection()

            Section {
                ForEach(model.versions) { component in
                    LabeledContent {
                        Text(component.version ?? String(localized: "not installed"))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } label: {
                        Text(verbatim: component.name)
                    }
                }
            } header: {
                Text("Versions")
            }

            Section {
                LabeledContent {
                    Text(verbatim: model.valetBinary ?? "—")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } label: {
                    Label("Valet binary", systemImage: "terminal")
                }
                LabeledContent {
                    Text(verbatim: Shell.brewPrefix).foregroundStyle(.secondary)
                } label: {
                    Label("Homebrew", systemImage: "shippingbox")
                }
            } header: {
                Text("Environment")
            } footer: {
                Text("Community project, not affiliated with Laravel. No background task: state is read when you open the menu.")
                    .settingsCaption()
            }
        }
        .formStyle(.grouped)
    }
}

struct UpdatesSection: View {
    @AppStorage(Updater.autoCheckKey) private var autoCheck = true
    private var updater: Updater { Updater.shared }

    var body: some View {
        Section {
            Toggle(isOn: $autoCheck) {
                Label("Check for updates automatically", systemImage: "arrow.triangle.2.circlepath")
            }
            HStack {
                Label {
                    Text(updater.statusMessage ?? String(localized: "Version \(currentVersion)"))
                } icon: {
                    Image(systemName: updater.available == nil ? "checkmark.seal" : "arrow.down.circle.fill")
                        .foregroundStyle(updater.available == nil ? Color.secondary : Color.accentColor)
                }
                Spacer()
                if updater.isChecking {
                    ProgressView().controlSize(.small)
                } else if let update = updater.available {
                    Button("Release Notes") { updater.openReleaseNotes(update) }
                    Button("Download") { updater.download(update) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Check Now") { Task { await updater.check(manual: true) } }
                }
            }
            HStack {
                Text("Homebrew users can update with `brew upgrade purevalet`.")
                    .settingsCaption()
                Spacer()
                Link("All releases", destination: URL(string: "https://github.com/aubinvan/purevalet/releases")!)
                    .font(.caption)
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("At most once a day, one request to GitHub. Nothing is downloaded or installed without you.")
                .settingsCaption()
        }
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

// MARK: - Shared

struct NotInstalledPlaceholder: View {
    var body: some View {
        ContentUnavailableView {
            Label("Valet not installed", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Install Laravel Valet (see the General tab), then refresh.")
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
                    Button("Details") { showDetails.toggle() }
                        .popover(isPresented: $showDetails, arrowEdge: .top) {
                            ScrollView {
                                Text(verbatim: model.lastOutput)
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
    /// Small secondary helper text, like in macOS System Settings.
    func settingsCaption() -> some View {
        font(.caption).foregroundStyle(.secondary)
    }
}
