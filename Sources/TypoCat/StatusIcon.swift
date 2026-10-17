import AppKit

/// Manee's head as a menu-bar template image: filled, with the eyes cut out,
/// so it stays legible at 16 pt and follows light and dark menu bars.
enum StatusIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            // Drawn on a 100-unit grid: the app icon's round cat head, eyes cut out.
            cg.scaleBy(x: 0.18, y: 0.18)
            cg.setFillColor(NSColor.black.cgColor)
            let ears = CGMutablePath()
            ears.move(to: CGPoint(x: 10, y: 52)); ears.addQuadCurve(to: CGPoint(x: 16, y: 4), control: CGPoint(x: 4, y: 10))
            ears.addQuadCurve(to: CGPoint(x: 46, y: 26), control: CGPoint(x: 26, y: 0)); ears.closeSubpath()
            ears.move(to: CGPoint(x: 90, y: 52)); ears.addQuadCurve(to: CGPoint(x: 84, y: 4), control: CGPoint(x: 96, y: 10))
            ears.addQuadCurve(to: CGPoint(x: 54, y: 26), control: CGPoint(x: 74, y: 0)); ears.closeSubpath()
            cg.addPath(ears); cg.fillPath()
            cg.fillEllipse(in: CGRect(x: 2, y: 20, width: 96, height: 78))
            // Big round eyes, like Manee's.
            cg.setBlendMode(.clear)
            cg.fillEllipse(in: CGRect(x: 22, y: 46, width: 20, height: 24))
            cg.fillEllipse(in: CGRect(x: 58, y: 46, width: 20, height: 24))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "TypoCat"
        return image
    }()
}
