import AppKit
import SwiftUI

@main
struct ValetDesktopApp: App {
    @State private var model = ValetModel()

    init() {
        // `ValetDesktop --snapshot <dossier>` : capture la fenêtre de réglages (un PNG par onglet) puis quitte.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.render(into: URL(fileURLWithPath: args[i + 1]))
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
enum Snapshot {
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
