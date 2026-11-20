import SwiftUI

@main
struct ValetDesktopApp: App {
    @State private var model = ValetModel()

    init() {
        // `ValetDesktop --snapshot fichier.png` : rend le menu dans une image puis quitte (vérification sans clic).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.render(to: URL(fileURLWithPath: args[i + 1]))
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
enum Snapshot {
    static func render(to url: URL) {
        Task { @MainActor in
            let model = ValetModel()
            await model.refresh()
            let view = ContentView()
                .environment(model)
                .background(Color(nsColor: .windowBackgroundColor))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                print("snapshot: \(url.path)")
            }
            exit(0)
        }
    }
}
