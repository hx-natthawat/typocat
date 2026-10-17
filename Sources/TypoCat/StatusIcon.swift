import AppKit

/// The cat-eared keycap as a menu-bar template image: filled, with the eyes cut out,
/// so it stays legible at 16 pt and follows light and dark menu bars.
enum StatusIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            // Drawn on the 100-unit grid of docs/brand/mark.svg.
            cg.scaleBy(x: 0.18, y: 0.18)
            cg.setFillColor(NSColor.black.cgColor)
            let ears = CGMutablePath()
            ears.addLines(between: [CGPoint(x: 12, y: 34), CGPoint(x: 21, y: 3), CGPoint(x: 42, y: 22)])
            ears.addLines(between: [CGPoint(x: 88, y: 34), CGPoint(x: 79, y: 3), CGPoint(x: 58, y: 22)])
            cg.addPath(ears); cg.fillPath()
            cg.addPath(CGPath(roundedRect: CGRect(x: 6, y: 16, width: 88, height: 80), cornerWidth: 22, cornerHeight: 22, transform: nil))
            cg.fillPath()
            // Manee's eyes, cut out. (A cut-out diagonal split read as a "disabled" slash.)
            cg.setBlendMode(.clear)
            cg.fillEllipse(in: CGRect(x: 23, y: 44, width: 18, height: 22))
            cg.fillEllipse(in: CGRect(x: 59, y: 44, width: 18, height: 22))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "TypoCat"
        return image
    }()
}
