import Foundation

/// Describes the game embedded in a built app: `Contents/Resources/Game/game.json`.
/// Written by GB App Builder, read by the player.
struct GameManifest: Codable, Equatable {
    /// Name of the app and of the game as shown to the user.
    var title: String
    /// "gb", "gbc" or "gba".
    var system: String
    /// File name of the ROM inside `Resources/Game/`. Its base name names the save file (`<base>.sav`), as in mGBA.
    var romFile: String
    /// No-Intro name from the DAT match, if any.
    var romName: String?
    var crc32: String?
    /// Title and code from the ROM header.
    var headerTitle: String?
    var gameCode: String?
    /// mGBA BIOS config key ("gba.bios", "gb.bios", "gbc.bios", "sgb.bios") → file name inside `Resources/BIOS/`.
    var bios: [String: String]
    /// Folder name under `~/Library/Application Support/mGBA Games/`.
    var dataFolder: String
    var build: BuildInfo?
    /// The game's manual, if the builder found or was given one.
    var manual: ManualInfo?

    struct ManualInfo: Codable, Equatable {
        /// File name inside `Resources/Game/` (`Manual.pdf`).
        var file: String
        /// Where it came from: an archive.org download URL, or the name of the file the user chose.
        var source: String?
    }

    struct BuildInfo: Codable, Equatable {
        var builderVersion: String
        var mgbaVersion: String?
        var date: String
    }

    static let fileName = "game.json"
    static let defaultsFileName = "defaults.ini"
    static let manualFileName = "Manual.pdf"

    var systemName: String {
        switch system {
        case "gba": return "Game Boy Advance"
        case "gbc": return "Game Boy Color"
        default: return "Game Boy"
        }
    }
}

enum GamePaths {
    /// `~/Library/Application Support/mGBA Games`
    static var supportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("mGBA Games", isDirectory: true)
    }

    static func dataFolder(_ name: String) -> URL {
        supportRoot.appendingPathComponent(name, isDirectory: true)
    }

    /// Makes a string safe as a single path component.
    static func sanitize(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\\0")
        let cleaned = name.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Game" : cleaned
    }
}
