import AppKit

/// Small coloured dots for the menu bar menu. Native menus keep the colours of non-template images
/// (SF Symbols tinted in SwiftUI would turn grey there). Menus cannot animate, so the dot is static.
enum StatusDot {
    enum State { case ok, down, unknown }

    static func image(_ state: State) -> NSImage {
        switch state {
        case .ok: return green
        case .down: return red
        case .unknown: return gray
        }
    }

    private static let green = make(.systemGreen)
    private static let red = make(.systemRed)
    private static let gray = make(.systemGray)

    private static func make(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
