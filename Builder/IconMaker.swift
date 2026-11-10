import AppKit
import Foundation

/// Box art from the libretro thumbnail server, as RetroApp does: the No-Intro name (from the DAT match,
/// else the ROM's file name) → `Named_Boxarts/<name>.png`, then the title screen as a fallback.
enum BoxArt {
    enum Kind: String, CaseIterable {
        case boxart = "Named_Boxarts"
        case title = "Named_Titles"
        case snap = "Named_Snaps"
    }

    /// libretro thumbnail names replace &*/:`<>?\| with _.
    static func thumbnailName(_ name: String) -> String {
        String(name.map { "&*/:`<>?\\|\"".contains($0) ? "_" : $0 })
    }

    static func urls(system: String, name: String, kind: Kind) -> [URL] {
        let file = thumbnailName(name) + ".png"
        var result: [URL] = []
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#"))
        if let s = system.addingPercentEncoding(withAllowedCharacters: allowed),
           let f = file.addingPercentEncoding(withAllowedCharacters: allowed),
           let url = URL(string: "https://thumbnails.libretro.com/\(s)/\(kind.rawValue)/\(f)") {
            result.append(url)
        }
        let repo = system.replacingOccurrences(of: " ", with: "_")
        if let f = file.addingPercentEncoding(withAllowedCharacters: allowed),
           let url = URL(string: "https://raw.githubusercontent.com/libretro-thumbnails/\(repo)/master/\(kind.rawValue)/\(f)") {
            result.append(url)
        }
        return result
    }

    /// Tries each name and kind in order; returns the first image found.
    static func fetch(system: String, names: [String], kinds: [Kind] = [.boxart, .title]) async -> (NSImage, URL)? {
        var seen = Set<String>()
        for kind in kinds {
            for name in names where !name.isEmpty && seen.insert("\(kind)/\(name)").inserted {
                for url in urls(system: system, name: name, kind: kind) {
                    var request = URLRequest(url: url, timeoutInterval: 15)
                    request.setValue("GB-App-Builder", forHTTPHeaderField: "User-Agent")
                    guard let (data, response) = try? await URLSession.shared.data(for: request),
                          (response as? HTTPURLResponse)?.statusCode == 200,
                          let image = NSImage(data: data), image.isValid
                    else { continue }
                    return (image, url)
                }
            }
        }
        return nil
    }
}

enum IconMaker {
    /// The image centred on a transparent square canvas (aspect kept), with a soft shadow.
    static func squareImage(_ image: NSImage, size: CGFloat = 1024) -> NSImage {
        let canvas = NSImage(size: NSSize(width: size, height: size))
        canvas.lockFocus()
        defer { canvas.unlockFocus() }
        guard let context = NSGraphicsContext.current else { return canvas }
        context.imageInterpolation = .high
        let source = image.size
        let inset = size * 0.06
        let box = size - inset * 2
        let scale = min(box / max(source.width, 1), box / max(source.height, 1))
        let drawSize = NSSize(width: source.width * scale, height: source.height * scale)
        let rect = NSRect(x: (size - drawSize.width) / 2, y: (size - drawSize.height) / 2, width: drawSize.width, height: drawSize.height)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = size * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
        shadow.set()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        return canvas
    }

    static func pngData(_ image: NSImage, pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Writes an .icns with every size macOS uses (via iconutil).
    static func writeICNS(_ image: NSImage, to url: URL) throws {
        let square = squareImage(image)
        let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("icon-\(UUID().uuidString).iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: iconset) }
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                guard let data = pngData(square, pixels: points * scale) else { continue }
                try data.write(to: iconset.appendingPathComponent(name))
            }
        }
        try? FileManager.default.removeItem(at: url)
        try ROMInspector.run("/usr/bin/iconutil", ["-c", "icns", "-o", url.path, iconset.path])
    }

    /// The default icon for a system when no box art is found: mGBA's own system artwork, bundled with the builder.
    static func defaultImage(system: String) -> NSImage? {
        let name = system == "gba" ? "gba-icon" : (system == "gbc" ? "gbc-icon" : "gb-icon")
        if let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "SystemIcons"), let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(named: NSImage.applicationIconName)
    }
}
