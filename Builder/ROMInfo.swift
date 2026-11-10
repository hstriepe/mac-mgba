import Foundation

/// A ROM opened in the builder: the file (unzipped if it came in a ZIP), its header and checksum.
struct ROMInfo: Equatable {
    /// The ROM file itself (in a temporary folder when it came from a ZIP).
    let url: URL
    /// What the user opened (the .zip or the ROM).
    let sourceURL: URL
    let system: String
    let headerTitle: String
    let gameCode: String
    let crc32: String
    let size: Int
    /// GB: CGB flag at 0x143 (0x80 = works on both, 0xC0 = GBC only); SGB flag at 0x146 (0x03 = SGB features).
    let cgbFlag: UInt8
    let sgbSupport: Bool
    /// Other ROMs found in the same ZIP (not used).
    let otherFilesInArchive: [String]

    var fileName: String { url.lastPathComponent }
    var baseName: String { url.deletingPathExtension().lastPathComponent }

    var systemName: String {
        switch system {
        case "gba": return "Game Boy Advance"
        case "gbc": return cgbFlag == 0xC0 ? "Game Boy Color" : "Game Boy Color (also runs on Game Boy)"
        default: return sgbSupport ? "Game Boy (Super Game Boy enhanced)" : "Game Boy"
        }
    }

    /// The libretro/No-Intro system name used for DATs and box art.
    var libretroSystem: String {
        switch system {
        case "gba": return "Nintendo - Game Boy Advance"
        case "gbc": return "Nintendo - Game Boy Color"
        default: return "Nintendo - Game Boy"
        }
    }

    /// mGBA BIOS config keys and the files they need. A GB/GBC game can run as any Game Boy model
    /// (Settings › Game Boy › Model), so it gets all three Game Boy BIOS files.
    var biosFiles: [String: String] {
        system == "gba" ? ["gba.bios": "gba_bios.bin"]
            : ["gb.bios": "gb_bios.bin", "gbc.bios": "gbc_bios.bin", "sgb.bios": "sgb_bios.bin"]
    }

    static let romExtensions: Set<String> = ["gb", "gbc", "gba", "sgb", "agb", "cgb"]
}

enum ROMError: LocalizedError {
    case unreadable(URL)
    case noROMInArchive(URL)
    case notAROM(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): return "“\(url.lastPathComponent)” could not be read."
        case .noROMInArchive(let url): return "“\(url.lastPathComponent)” holds no .gb, .gbc or .gba file."
        case .notAROM(let url): return "“\(url.lastPathComponent)” is not a Game Boy or Game Boy Advance ROM."
        }
    }
}

enum ROMInspector {
    /// Opens a .gb/.gbc/.gba file or a ZIP holding one.
    static func open(_ source: URL) throws -> ROMInfo {
        var romURL = source
        var others: [String] = []
        if source.pathExtension.lowercased() == "zip" {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("gb-appbuilder-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", ["-x", "-k", source.path, folder.path])
            let found = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects.compactMap { $0 as? URL } ?? []
            let roms = found
                .filter { ROMInfo.romExtensions.contains($0.pathExtension.lowercased()) && !$0.path.contains("__MACOSX") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard let first = roms.first else { throw ROMError.noROMInArchive(source) }
            romURL = first
            others = roms.dropFirst().map(\.lastPathComponent)
        }
        guard let data = try? Data(contentsOf: romURL, options: .mappedIfSafe) else { throw ROMError.unreadable(romURL) }
        return try inspect(data: data, url: romURL, source: source, others: others)
    }

    static func inspect(data: Data, url: URL, source: URL, others: [String] = []) throws -> ROMInfo {
        let bytes = [UInt8](data.prefix(0x150))
        let crc = String(format: "%08X", CRC32.checksum(data))
        func ascii(_ range: Range<Int>) -> String {
            guard bytes.count >= range.upperBound else { return "" }
            let chars = bytes[range].prefix { $0 != 0 }.map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : " " }
            return String(chars).trimmingCharacters(in: .whitespaces)
        }

        // GBA: fixed value 0x96 at 0xB2 and the Nintendo logo at 0x04.
        if bytes.count >= 0xC0, bytes[0xB2] == 0x96 {
            return ROMInfo(url: url, sourceURL: source, system: "gba", headerTitle: ascii(0xA0..<0xAC), gameCode: ascii(0xAC..<0xB0),
                           crc32: crc, size: data.count, cgbFlag: 0, sgbSupport: false, otherFilesInArchive: others)
        }
        // GB/GBC: the Nintendo logo at 0x104 starts CE ED 66 66.
        if bytes.count >= 0x150, bytes[0x104] == 0xCE, bytes[0x105] == 0xED, bytes[0x106] == 0x66, bytes[0x107] == 0x66 {
            let cgb = bytes[0x143]
            let isCGB = cgb == 0x80 || cgb == 0xC0
            // The title is 16 bytes on old carts, 15 on GBC carts (some with a 4-character code inside; not split here).
            return ROMInfo(url: url, sourceURL: source, system: isCGB ? "gbc" : "gb",
                           headerTitle: ascii(0x134..<(isCGB ? 0x143 : 0x144)), gameCode: "",
                           crc32: crc, size: data.count, cgbFlag: cgb, sgbSupport: bytes[0x146] == 0x03, otherFilesInArchive: others)
        }
        throw ROMError.notAROM(url)
    }

    static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "GBAppBuilder", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\((tool as NSString).lastPathComponent) failed (exit \(process.terminationStatus))."])
        }
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for byte in buffer { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        }
        return crc ^ 0xFFFFFFFF
    }
}

/// No-Intro DATs (from libretro-database), bundled in the builder: CRC32 → canonical game name.
final class DatIndex {
    static let shared = DatIndex()
    private var names: [String: [String: String]] = [:]   // system → crc → name
    private let lock = NSLock()

    func name(crc: String, system: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if names[system] == nil { names[system] = load(system: system) }
        return names[system]?[crc.uppercased()]
    }

    private func load(system: String) -> [String: String] {
        guard let url = Bundle.main.url(forResource: system, withExtension: "dat", subdirectory: "DATs"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [:] }
        var result: [String: String] = [:]
        var current: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("name \"") {
                current = trimmed.dropFirst(6).split(separator: "\"").first.map(String.init)
            } else if trimmed.hasPrefix("rom ("), let current, let range = trimmed.range(of: "crc ") {
                let crc = trimmed[range.upperBound...].prefix(8)
                result[String(crc).uppercased()] = current
            }
        }
        return result
    }
}

extension String {
    /// "Advance Wars (USA) (Rev 1)" → "Advance Wars"; "Legend of Zelda, The - Link's Awakening" → "The Legend of Zelda - Link's Awakening".
    var cleanGameTitle: String {
        var title = self
        if let index = title.firstIndex(of: "(") { title = String(title[..<index]) }
        if let index = title.firstIndex(of: "[") { title = String(title[..<index]) }
        title = title.trimmingCharacters(in: .whitespaces)
        for article in ["The", "A", "An"] {
            let marker = ", \(article)"
            if let range = title.range(of: marker) {
                let after = title[range.upperBound...]
                if after.isEmpty || after.hasPrefix(" -") || after.hasPrefix(":") {
                    title = "\(article) " + title[..<range.lowerBound] + after
                    break
                }
            }
        }
        return title.trimmingCharacters(in: .whitespaces)
    }
}
