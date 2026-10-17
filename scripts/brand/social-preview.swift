import AppKit
// Usage: social-preview <app-icon.svg> <fonts dir> <out.png>. 1280x640, for GitHub and link previews.
let a = CommandLine.arguments
for f in ["Rubik.ttf", "NotoSansThai.ttf", "PlexMono.ttf"] {
    CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: a[2] + "/" + f) as CFURL, .process, nil)
}
func font(_ family: String, _ size: CGFloat, weight: CGFloat? = nil) -> NSFont {
    var attrs: [NSFontDescriptor.AttributeName: Any] = [.family: family]
    if let weight { attrs[NSFontDescriptor.AttributeName(kCTFontVariationAttribute as String)] = [0x77676874: weight] }
    return NSFont(descriptor: NSFontDescriptor(fontAttributes: attrs), size: size)!
}
func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: alpha)
}
let ink = hex(0x142220), sand = hex(0xEEF2EE), lagoon = hex(0x0B7A75), lagoonLight = hex(0x4CC3B9), marigold = hex(0xF2A12B), coral = hex(0xE5603D)

let W = 1280, H = 640
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
// Flip so y grows downward like a page.
ctx.cgContext.translateBy(x: 0, y: CGFloat(H)); ctx.cgContext.scaleBy(x: 1, y: -1)
let flipped = NSAffineTransform()

ink.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
// Soft lagoon glow behind the icon.
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [lagoon.withAlphaComponent(0.5).cgColor, lagoon.withAlphaComponent(0.18).cgColor, lagoon.withAlphaComponent(0).cgColor] as CFArray,
                      locations: [0, 0.5, 1])!
ctx.cgContext.drawRadialGradient(glow, startCenter: CGPoint(x: 300, y: 330), startRadius: 0,
                                 endCenter: CGPoint(x: 300, y: 330), endRadius: 420, options: [])

func text(_ s: String, _ f: NSFont, _ c: NSColor, at p: NSPoint, kern: CGFloat = 0) -> NSSize {
    let str = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c, .kern: kern])
    NSGraphicsContext.saveGraphicsState()
    // Text must be drawn unflipped: flip locally around its baseline box.
    let size = str.size()
    let t = ctx.cgContext
    t.saveGState(); t.translateBy(x: p.x, y: p.y + size.height); t.scaleBy(x: 1, y: -1)
    str.draw(at: .zero)
    t.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return size
}

// App icon (drawn unflipped the same way).
let icon = NSImage(contentsOf: URL(fileURLWithPath: a[1]))!
do {
    let t = ctx.cgContext; t.saveGState(); t.translateBy(x: 40, y: 600); t.scaleBy(x: 1, y: -1)
    icon.draw(in: NSRect(x: 0, y: 0, width: 520, height: 520)); t.restoreGState()
}

let left: CGFloat = 560
let wordFont = font("Rubik", 124, weight: 600)
let typo = text("Typo", wordFont, sand, at: NSPoint(x: left, y: 92), kern: -2)
_ = text("Cat", wordFont, marigold, at: NSPoint(x: left + typo.width - 2, y: 92), kern: -2)
_ = text("Wrong keyboard or a slip of the paw?", font("Rubik", 36, weight: 400), sand.withAlphaComponent(0.88), at: NSPoint(x: left + 4, y: 252))
_ = text("Keep typing.", font("Rubik", 36, weight: 500), lagoonLight, at: NSPoint(x: left + 4, y: 298))

// Before → after chips.
let chips: [(String, String, String)] = [("ghbdtn", "привет", "Rubik"), ("l;ylfu", "สวัสดี", "Noto Sans Thai"),
                                         ("akuo", "שלום", "Rubik"), ("recieve", "receive", "Rubik")]
var x = left + 4, y: CGFloat = 384
for (i, (typed, fixed, family)) in chips.enumerated() {
    if i == 2 { x = left + 4; y += 74 }
    let mono = font("IBM Plex Mono", 24), out = font(family, 27, weight: 500), arrow = font("Rubik", 24, weight: 500)
    let tw = NSAttributedString(string: typed, attributes: [.font: mono]).size().width
    let aw = NSAttributedString(string: "  →  ", attributes: [.font: arrow]).size().width
    let fw = NSAttributedString(string: fixed, attributes: [.font: out]).size().width
    let w = 22 + tw + aw + fw + 22
    let chip = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: 56), xRadius: 16, yRadius: 16)
    hex(0x1E3330).setFill(); chip.fill()
    hex(0x2F4A46).setStroke(); chip.lineWidth = 1.5; chip.stroke()
    let ts = text(typed, mono, coral.blended(withFraction: 0.25, of: sand)!, at: NSPoint(x: x + 22, y: y + 12))
    // strike through the wrong-layout text
    coral.withAlphaComponent(0.8).setStroke()
    let strike = NSBezierPath(); strike.move(to: NSPoint(x: x + 20, y: y + 29)); strike.line(to: NSPoint(x: x + 24 + ts.width, y: y + 29)); strike.lineWidth = 2; strike.stroke()
    _ = text("  →  ", arrow, sand.withAlphaComponent(0.5), at: NSPoint(x: x + 22 + tw, y: y + 13))
    _ = text(fixed, out, sand, at: NSPoint(x: x + 22 + tw + aw, y: y + (family == "Noto Sans Thai" ? 6 : 11)))
    x += w + 16
}
_ = text("Open source  ·  macOS menu-bar app  ·  any keyboard layout", font("Rubik", 21, weight: 400), sand.withAlphaComponent(0.55), at: NSPoint(x: left + 4, y: 560))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3]))
