// Génère, à partir de Resources/source/logo.png (fond transparent) :
//   - Resources/AppIcon.icns       : icône de l'appli (logo sur carré arrondi blanc)
//   - Resources/MenuBarIcon.png/@2x : icône « template » monochrome pour la barre de menus
//   - docs/icon.png                : icône pour le README
// Usage : swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let logoURL = root.appendingPathComponent("Resources/source/logo.png")
guard let logo = NSImage(contentsOf: logoURL),
      let logoRep = logo.representations.first as? NSBitmapImageRep else {
    fatalError("Logo introuvable : \(logoURL.path)")
}
// Travaille en pixels, quelle que soit la résolution (dpi) déclarée dans le PNG.
logo.size = NSSize(width: logoRep.pixelsWide, height: logoRep.pixelsHigh)

/// Zone non transparente du logo (en coordonnées AppKit, origine en bas à gauche).
let trimmed: NSRect = {
    var minX = logoRep.pixelsWide, minY = logoRep.pixelsHigh, maxX = 0, maxY = 0
    for y in 0..<logoRep.pixelsHigh {
        for x in 0..<logoRep.pixelsWide where (logoRep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    let h = CGFloat(logoRep.pixelsHigh)
    return NSRect(x: CGFloat(minX), y: h - CGFloat(maxY + 1), width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
}()

func bitmap(_ w: Int, _ h: Int, _ draw: (NSRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    draw(NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Dessine le logo rogné, centré dans `box`, en gardant ses proportions.
func drawLogo(in box: NSRect) {
    let scale = min(box.width / trimmed.width, box.height / trimmed.height)
    let size = NSSize(width: trimmed.width * scale, height: trimmed.height * scale)
    let dest = NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
    logo.draw(in: dest, from: trimmed, operation: .sourceOver, fraction: 1)
}

func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }

// 1. Icône de l'appli : carré arrondi blanc (grille Apple : 824/1024), léger dégradé et ombre.
func appIcon(_ size: Int) -> NSBitmapImageRep {
    bitmap(size, size) { rect in
        let s = rect.width
        let tile = NSRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
        let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = s * 0.025
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
        shadow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(starting: .white, ending: NSColor(white: 0.93, alpha: 1))!.draw(in: path, angle: -90)
        drawLogo(in: tile.insetBy(dx: tile.width * 0.17, dy: tile.height * 0.17))
    }
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(appIcon(base)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(appIcon(base * 2)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
try png(appIcon(256)).write(to: root.appendingPathComponent("docs/icon.png"))

// 2. Icône de barre de menus : silhouette noire (template), 18 pt de haut.
func menuBarIcon(height: Int) -> NSBitmapImageRep {
    let width = Int((CGFloat(height) * trimmed.width / trimmed.height).rounded(.up))
    return bitmap(width, height) { rect in
        drawLogo(in: rect)
        NSColor.black.set()
        rect.fill(using: .sourceAtop)
    }
}
try png(menuBarIcon(height: 18)).write(to: root.appendingPathComponent("Resources/MenuBarIcon.png"))
try png(menuBarIcon(height: 36)).write(to: root.appendingPathComponent("Resources/MenuBarIcon@2x.png"))

print(iconutil.terminationStatus == 0 ? "OK : AppIcon.icns, MenuBarIcon.png, docs/icon.png" : "iconutil a échoué")
