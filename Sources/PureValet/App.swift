import AppKit
import SwiftUI

@main
struct PureValetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = ValetModel.shared

    init() {
        Preferences.register()
        // `PureValet --snapshot <folder>`: captures the settings window (one PNG per tab), then quits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.isActive = true
            Snapshot.render(into: URL(fileURLWithPath: args[i + 1]))
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Starts the services at launch (optional) and stops them when the app quits (default),
/// so PureValet alone drives the whole environment and nothing is left running afterwards.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Snapshot.isActive, Preferences.startOnLaunch else { return }
        Task {
            await ValetModel.shared.refresh()
            await ValetModel.shared.startAll()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Snapshot.isActive, Preferences.stopOnQuit, !quitting else { return .terminateNow }
        quitting = true
        var replied = false
        let finish = {
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        Task {
            await ValetModel.shared.stopEverythingForQuit()
            finish()
        }
        // Never block quitting (e.g. a password prompt left open): give up after 60 s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { finish() }
        return .terminateLater
    }
}

/// Menu bar logo: a template image (adapts to light/dark mode), dimmed while Valet is not running.
struct MenuBarLabel: View {
    let model: ValetModel

    var body: some View {
        let active = model.isInstalled && model.running == true
        if let image = active ? MenuBarIcon.active : MenuBarIcon.inactive {
            Image(nsImage: image)
        } else {
            Image(systemName: model.menuBarSymbol)
        }
    }
}

enum MenuBarIcon {
    private static let base: NSImage? = Bundle.main.image(forResource: "MenuBarIcon")

    static let active: NSImage? = {
        guard let image = base?.copy() as? NSImage else { return nil }
        image.isTemplate = true
        return image
    }()

    static let inactive: NSImage? = {
        guard let base else { return nil }
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.4)
            return true
        }
        image.isTemplate = true
        return image
    }()
}

@MainActor
enum Snapshot {
    static var isActive = false

    static func render(into directory: URL) {
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let model = ValetModel()
            await model.refresh()
            let selection = TabSelection()
            let window = SettingsWindowController.makeWindow(model: model, selection: selection)
            window.alphaValue = 0
            window.orderFrontRegardless()

            for tab in SettingsTab.allCases {
                selection.tab = tab
                try? await Task.sleep(for: .milliseconds(600))
                guard let view = window.contentView?.superview ?? window.contentView else { continue }
                let bounds = view.bounds
                guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { continue }
                view.cacheDisplay(in: bounds, to: rep)
                let url = directory.appendingPathComponent("\(tab.rawValue).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("snapshot: \(url.path)")
            }
            exit(0)
        }
    }
}
