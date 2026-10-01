// Renders the 1024×1024 app icon. App Store Connect needs it opaque, so
// flatten afterwards: python3 -c "from PIL import Image; p=...; Image.open(p).convert('RGB').save(p)"
// Usage: swift scripts/make-icon.swift Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//        swift scripts/make-icon.swift Resources/Assets.xcassets/AppIcon-Local.appiconset/AppIcon.png --local
// `--local` draws the Debug-build icon: orange, with a "LOCAL" band, so it
// can't be mistaken for the TestFlight app on the home screen.
import AppKit

let size = 1024.0
let out = CommandLine.arguments[1]
let local = CommandLine.arguments.contains("--local")
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let top = local ? NSColor(srgbRed: 1.00, green: 0.62, blue: 0.20, alpha: 1) : NSColor(srgbRed: 0.36, green: 0.47, blue: 0.98, alpha: 1)
let bottom = local ? NSColor(srgbRed: 0.93, green: 0.36, blue: 0.05, alpha: 1) : NSColor(srgbRed: 0.20, green: 0.27, blue: 0.80, alpha: 1)
NSGradient(starting: top, ending: bottom)!.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 520, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let symbol = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
let s = symbol.size
let lift = local ? 90.0 : 0
symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2 - 10 + lift, width: s.width, height: s.height))

if local {
    // White band across the lower third, clear of the rounded corners.
    let band = NSRect(x: 0, y: 150, width: size, height: 190)
    NSColor.white.setFill()
    band.fill()
    let text = NSAttributedString(string: "LOCAL", attributes: [
        .font: NSFont.systemFont(ofSize: 150, weight: .heavy),
        .foregroundColor: bottom,
        .kern: 12,
    ])
    let t = text.size()
    text.draw(at: NSPoint(x: (size - t.width) / 2, y: band.midY - t.height / 2))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
