// Draws GB App Builder's icon from mGBA's artwork (mgba/res/mgba-1024.png):
//   Builder/Icon/AppIcon-1024.png          the full icon (macOS grid: 824 pt body on a 1024 canvas)
//   Builder/Icon/Foreground-1024.png       the handheld and the hammer badge on transparency, a layer for Icon Composer
//   Builder/Icon/Background-1024.png       the background gradient alone, the other Icon Composer layer
// Run: swift scripts/make-builder-icon.swift  (from the repository root)
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let art = root.appendingPathComponent("mgba/res/mgba-1024.png")
let out = root.appendingPathComponent("Builder/Icon", isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
guard let handheld = NSImage(contentsOf: art) else { fatalError("missing \(art.path)") }

let size: CGFloat = 1024
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185

func render(_ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func background(in rect: NSRect) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius * rect.width / 824, yRadius: radius * rect.width / 824)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.11, alpha: 1),
        NSColor(calibratedRed: 0.22, green: 0.27, blue: 0.38, alpha: 1),
    ])!
    gradient.draw(in: path, angle: 90)
    // A soft light from the top
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
    glow.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: 270)
    NSGraphicsContext.restoreGraphicsState()
}

func foreground() {
    // The handheld, slightly above centre
    let width: CGFloat = 760
    let height = width * handheld.size.height / handheld.size.width
    let rect = NSRect(x: (size - width) / 2 - 10, y: (size - height) / 2 + 40, width: width, height: height)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    handheld.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    // Badge: a hammer on an orange disc, bottom right
    let badge = NSRect(x: 600, y: 150, width: 270, height: 270)
    NSGraphicsContext.saveGraphicsState()
    let badgeShadow = NSShadow()
    badgeShadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
    badgeShadow.shadowBlurRadius = 18
    badgeShadow.shadowOffset = NSSize(width: 0, height: -8)
    badgeShadow.set()
    NSGradient(colors: [NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.18, alpha: 1),
                        NSColor(calibratedRed: 0.93, green: 0.38, blue: 0.10, alpha: 1)])!
        .draw(in: NSBezierPath(ovalIn: badge), angle: 270)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.85).setStroke()
    let ring = NSBezierPath(ovalIn: badge.insetBy(dx: 6, dy: 6))
    ring.lineWidth = 8
    ring.stroke()
    let config = NSImage.SymbolConfiguration(pointSize: 150, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let hammer = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = hammer.size
        hammer.draw(in: NSRect(x: badge.midX - s.width / 2, y: badge.midY - s.height / 2, width: s.width, height: s.height))
    }
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    let url = out.appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print(url.path)
}

write(render { background(in: body); foreground() }, "AppIcon-1024.png")
write(render { foreground() }, "Foreground-1024.png")
write(render { background(in: NSRect(x: 0, y: 0, width: size, height: size)) }, "Background-1024.png")
