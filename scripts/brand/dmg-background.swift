import AppKit
// Usage: dmg-background <fonts dir> <scale> <out.png>. The installer window is 640x420 pt;
// Finder draws the app at (170, 200) and Applications at (470, 200) on top of this.
let a = CommandLine.arguments
for f in ["Rubik.ttf", "NotoSansThai.ttf", "PlexMono.ttf"] {
    CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: a[1] + "/" + f) as CFURL, .process, nil)
}
let scale = CGFloat(Double(a[2])!)
func font(_ family: String, _ size: CGFloat, weight: CGFloat) -> NSFont {
    let attrs: [NSFontDescriptor.AttributeName: Any] = [
        .family: family, NSFontDescriptor.AttributeName(kCTFontVariationAttribute as String): [0x77676874: weight],
    ]
    return NSFont(descriptor: NSFontDescriptor(fontAttributes: attrs), size: size)!
}
func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: alpha)
}
let ink = hex(0x142220), sand = hex(0xEEF2EE), lagoon = hex(0x0B7A75), marigold = hex(0xF2A12B)

let W: CGFloat = 640, H: CGFloat = 420
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
// Points, not pixels: AppKit then draws at `scale`.
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let cg = ctx.cgContext
// Work top-down like Finder's coordinates: y = H - y.
func y(_ top: CGFloat) -> CGFloat { H - top }

sand.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
// A soft lagoon glow behind each icon slot.
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [lagoon.withAlphaComponent(0.16).cgColor, lagoon.withAlphaComponent(0).cgColor] as CFArray,
                      locations: [0, 1])!
for x: CGFloat in [170, 470] {
    cg.drawRadialGradient(glow, startCenter: CGPoint(x: x, y: y(200)), startRadius: 0,
                          endCenter: CGPoint(x: x, y: y(200)), endRadius: 120, options: [])
}

func centered(_ s: String, _ f: NSFont, _ c: NSColor, top: CGFloat, x: CGFloat = W / 2) {
    let str = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c])
    let size = str.size()
    str.draw(at: NSPoint(x: x - size.width / 2, y: y(top) - size.height))
}

let title = NSMutableAttributedString(string: "Drag Typo", attributes: [.font: font("Rubik", 26, weight: 600), .foregroundColor: ink])
title.append(NSAttributedString(string: "Cat", attributes: [.font: font("Rubik", 26, weight: 600), .foregroundColor: marigold]))
title.append(NSAttributedString(string: " into Applications", attributes: [.font: font("Rubik", 26, weight: 600), .foregroundColor: ink]))
title.draw(at: NSPoint(x: (W - title.size().width) / 2, y: y(40) - title.size().height))

// Dashed arc from the app to Applications, with an arrowhead.
cg.setStrokeColor(marigold.cgColor)
cg.setLineWidth(4)
cg.setLineCap(.round)
cg.setLineDash(phase: 0, lengths: [1, 11])
cg.move(to: CGPoint(x: 250, y: y(196)))
cg.addQuadCurve(to: CGPoint(x: 384, y: y(196)), control: CGPoint(x: 317, y: y(150)))
cg.strokePath()
cg.setLineDash(phase: 0, lengths: [])
cg.setLineJoin(.round)
cg.move(to: CGPoint(x: 372, y: y(178)))
cg.addLine(to: CGPoint(x: 390, y: y(198)))
cg.addLine(to: CGPoint(x: 366, y: y(204)))
cg.strokePath()

let body = font("Rubik", 12.5, weight: 400)
centered("First open: if macOS says it can't check TypoCat for malware, open", body, ink.withAlphaComponent(0.7), top: 330)
let tip = NSMutableAttributedString(string: "System Settings → Privacy & Security", attributes: [.font: font("Rubik", 12.5, weight: 600), .foregroundColor: ink.withAlphaComponent(0.85)])
tip.append(NSAttributedString(string: " and click ", attributes: [.font: body, .foregroundColor: ink.withAlphaComponent(0.7)]))
tip.append(NSAttributedString(string: "Open Anyway", attributes: [.font: font("Rubik", 12.5, weight: 600), .foregroundColor: ink.withAlphaComponent(0.85)]))
tip.append(NSAttributedString(string: ".", attributes: [.font: body, .foregroundColor: ink.withAlphaComponent(0.7)]))
tip.draw(at: NSPoint(x: (W - tip.size().width) / 2, y: y(349) - tip.size().height))
centered("Then allow Accessibility when TypoCat asks. It never saves or sends what you type.", body,
         ink.withAlphaComponent(0.7), top: 374)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3]))
