import AppKit
import Foundation

/// Everything one build needs.
struct BuildRequest {
    var rom: ROMInfo
    var appName: String
    var romName: String?
    var icon: NSImage?
    var outputFolder: URL
    var bundleIDPrefix: String
    /// A codesigning identity name, or "-" for ad hoc.
    var signingIdentity: String
    var biosFolder: URL?
    /// mGBA config keys written to the app's defaults.ini (the user's settings in the game app override them).
    var defaults: [String: String]
    /// The game's manual (a PDF), and where it came from (shown in the game's Help).
    var manual: URL? = nil
    var manualSource: String? = nil
}

struct BuildResult {
    let appURL: URL
    let warnings: [String]
}

enum BuildError: LocalizedError {
    case noTemplate
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noTemplate: return "The player template is missing from GB App Builder (Contents/Resources/Template/GB Player.app). Rebuild the builder."
        case .failed(let message): return message
        }
    }
}

/// Copies the player template, puts the game, BIOS, icon and settings inside, renames and signs it.
enum AppAssembler {
    static var builderVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var mgbaVersion: String? {
        Bundle.main.url(forResource: "mgba-version", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var templateURL: URL? {
        Bundle.main.url(forResource: "GB Player", withExtension: "app", subdirectory: "Template")
    }

    /// The BIOS folder bundled with the builder (copied from the repository's bios/ when it was built).
    static var bundledBIOSFolder: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("BIOS", isDirectory: true)
    }

    static func bundleIdentifier(prefix: String, system: String, name: String) -> String {
        let slug = name.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" }
        let collapsed = String(slug).split(separator: "-").joined(separator: "-")
        return "\(prefix).\(system).\(collapsed.isEmpty ? "game" : collapsed)"
    }

    static func appURL(for request: BuildRequest) -> URL {
        request.outputFolder.appendingPathComponent(GamePaths.sanitize(request.appName) + ".app", isDirectory: true)
    }

    static func build(_ request: BuildRequest, log: (String) -> Void = { _ in }) throws -> BuildResult {
        guard let template = templateURL else { throw BuildError.noTemplate }
        let fm = FileManager.default
        var warnings: [String] = []
        let name = GamePaths.sanitize(request.appName)
        let app = appURL(for: request)

        try fm.createDirectory(at: request.outputFolder, withIntermediateDirectories: true)
        if fm.fileExists(atPath: app.path) {
            log("Moving the existing \(app.lastPathComponent) to the Trash")
            try fm.trashItem(at: app, resultingItemURL: nil)
        }
        log("Copying the player")
        try fm.copyItem(at: template, to: app)

        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let gameFolder = resources.appendingPathComponent("Game", isDirectory: true)
        let biosFolder = resources.appendingPathComponent("BIOS", isDirectory: true)
        try fm.createDirectory(at: gameFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: biosFolder, withIntermediateDirectories: true)

        // ROM, under its own file name: the save is then <name>.sav, as in mGBA, so existing saves can be dropped in.
        log("Adding \(request.rom.fileName)")
        try fm.copyItem(at: request.rom.url, to: gameFolder.appendingPathComponent(request.rom.fileName))

        // BIOS
        var bios: [String: String] = [:]
        for (key, file) in request.rom.biosFiles.sorted(by: { $0.key < $1.key }) {
            let candidates = [request.biosFolder, bundledBIOSFolder].compactMap { $0?.appendingPathComponent(file) }
            if let source = candidates.first(where: { fm.fileExists(atPath: $0.path) }) {
                try fm.copyItem(at: source, to: biosFolder.appendingPathComponent(file))
                bios[key] = file
                log("Adding BIOS \(file)")
            } else {
                warnings.append("\(file) not found: the game runs without it (\(key == "gba.bios" ? "mGBA's built-in BIOS replacement" : "no boot animation") ).")
            }
        }

        // Manual
        var manualInfo: GameManifest.ManualInfo?
        if let manual = request.manual {
            if fm.fileExists(atPath: manual.path) {
                log("Adding the manual (\(manual.lastPathComponent))")
                let target = gameFolder.appendingPathComponent(GameManifest.manualFileName)
                try fm.copyItem(at: manual, to: target)
                // Downloads arrive owner-only (0600); the app's files must be readable by everyone.
                try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
                manualInfo = .init(file: GameManifest.manualFileName, source: request.manualSource ?? manual.lastPathComponent)
            } else {
                warnings.append("The manual \(manual.lastPathComponent) was not found; the app has none.")
            }
        }

        // Manifest and defaults
        let date = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let manifest = GameManifest(title: request.appName, system: request.rom.system, romFile: request.rom.fileName,
                                    romName: request.romName, crc32: request.rom.crc32, headerTitle: request.rom.headerTitle,
                                    gameCode: request.rom.gameCode.isEmpty ? nil : request.rom.gameCode, bios: bios,
                                    dataFolder: name,
                                    build: .init(builderVersion: builderVersion, mgbaVersion: mgbaVersion, date: date),
                                    manual: manualInfo)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: gameFolder.appendingPathComponent(GameManifest.fileName))
        let ini = "; Defaults chosen in GB App Builder. The player's settings (config.ini in the game's data folder) override them.\n"
            + request.defaults.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
        try ini.write(to: gameFolder.appendingPathComponent(GameManifest.defaultsFileName), atomically: true, encoding: .utf8)

        // Icon
        let iconImage = request.icon ?? IconMaker.defaultImage(system: request.rom.system)
        if let iconImage {
            log("Writing the icon")
            try IconMaker.writeICNS(iconImage, to: resources.appendingPathComponent("AppIcon.icns"))
        }

        // Info.plist
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSMutableDictionary(contentsOf: plistURL) else { throw BuildError.failed("The template's Info.plist is unreadable.") }
        plist["CFBundleName"] = request.appName
        plist["CFBundleDisplayName"] = request.appName
        plist["CFBundleIdentifier"] = bundleIdentifier(prefix: request.bundleIDPrefix, system: request.rom.system, name: name)
        plist["CFBundleIconFile"] = "AppIcon"
        plist.removeObject(forKey: "CFBundleIconName")
        plist["CFBundleShortVersionString"] = "1.0"
        plist["CFBundleVersion"] = "1"
        plist["NSHumanReadableCopyright"] = "\(request.rom.libretroSystem.replacingOccurrences(of: "Nintendo - ", with: "")) game, emulated by mGBA (MPL 2.0)."
        plist["GBGameCRC32"] = request.rom.crc32
        guard plist.write(to: plistURL, atomically: true) else { throw BuildError.failed("Info.plist could not be written.") }

        // Signing (extended attributes from downloads or ZIPs make codesign fail)
        log("Signing (\(request.signingIdentity == "-" ? "ad hoc" : request.signingIdentity))")
        try ROMInspector.run("/usr/bin/xattr", ["-cr", app.path])
        try sign(app, identity: request.signingIdentity)
        // Finder caches icons by path; touching the bundle makes it pick up the new one.
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: app.path)
        log("Done: \(app.path)")
        return BuildResult(appURL: app, warnings: warnings)
    }

    static func sign(_ app: URL, identity: String) throws {
        var arguments = ["--force", "--sign", identity]
        if identity != "-" { arguments += ["--options", "runtime", "--timestamp"] }
        do {
            try ROMInspector.run("/usr/bin/codesign", arguments + [app.path])
        } catch where identity != "-" {
            // No network for the timestamp server: sign without a secure timestamp (fine locally, not for notarizing).
            try ROMInspector.run("/usr/bin/codesign", ["--force", "--sign", identity, "--options", "runtime", "--timestamp=none", app.path])
        }
        try ROMInspector.run("/usr/bin/codesign", ["--verify", "--strict", app.path])
    }

    /// Signing identities in the keychain ("Developer ID Application: …", "Apple Development: …").
    static func signingIdentities() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-identity", "-v", "-p", "codesigning"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        var result: [String] = []
        for line in text.split(separator: "\n") where !line.contains("REVOKED") {
            let parts = line.split(separator: "\"")
            if parts.count >= 2 { result.append(String(parts[1])) }
        }
        return Array(Set(result)).sorted { a, b in
            a.hasPrefix("Developer ID") != b.hasPrefix("Developer ID") ? a.hasPrefix("Developer ID") : a < b
        }
    }
}
