// Builds Resources/AppIcon.icon (Icon Composer format, macOS 26+): the logo as a layer on a
// light fill, with a dark fill for macOS's dark icon appearance. Compiled by actool in build.sh.
// Usage: swift scripts/make-icon-composer.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
guard let logo = NSImage(contentsOf: root.appendingPathComponent("Resources/source/logo.png")),
      let rep = logo.representations.first as? NSBitmapImageRep else { fatalError("Logo not found") }
logo.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)

// Trim transparent edges.
var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = 0, maxY = 0
for y in 0..<rep.pixelsHigh {
    for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}
let h = CGFloat(rep.pixelsHigh)
let trimmed = NSRect(x: CGFloat(minX), y: h - CGFloat(maxY + 1), width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))

// 1024×1024 transparent layer, logo centred at ~56 % of the canvas (Apple's icon grid keeps a safe margin).
let size = 1024
let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: canvas)!
ctx.imageInterpolation = .high
NSGraphicsContext.current = ctx
let box = CGFloat(size) * 0.56
let scale = min(box / trimmed.width, box / trimmed.height)
let w = trimmed.width * scale, hh = trimmed.height * scale
logo.draw(in: NSRect(x: (CGFloat(size) - w) / 2, y: (CGFloat(size) - hh) / 2, width: w, height: hh),
          from: trimmed, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

let icon = root.appendingPathComponent("Resources/AppIcon.icon")
try? FileManager.default.removeItem(at: icon)
try FileManager.default.createDirectory(at: icon.appendingPathComponent("Assets"), withIntermediateDirectories: true)
try canvas.representation(using: .png, properties: [:])!.write(to: icon.appendingPathComponent("Assets/logo.png"))

let json = """
{
  "fill" : {
    "automatic-gradient" : "extended-srgb:0.96000,0.96000,0.96000,1.00000"
  },
  "fill-specializations" : [
    {
      "appearance" : "dark",
      "value" : {
        "automatic-gradient" : "extended-srgb:0.16000,0.16000,0.17000,1.00000"
      }
    }
  ],
  "groups" : [
    {
      "layers" : [
        {
          "image-name" : "logo.png",
          "name" : "logo",
          "glass" : false
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.4
      },
      "translucency" : {
        "enabled" : false,
        "value" : 0.5
      }
    }
  ],
  "supported-platforms" : {
    "squares" : [
      "macOS"
    ]
  }
}

"""
try json.write(to: icon.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("OK : Resources/AppIcon.icon")
