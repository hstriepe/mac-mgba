import AppKit
import SwiftUI

/// GB App Builder: a window app, or a command-line tool when started with `--rom`
/// (`scripts/build-game.sh` uses that).
@main
enum BuilderMain {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--rom") || arguments.contains("--help") {
            exit(CommandLineBuild.run(Array(arguments.dropFirst())))
        }
        BuilderApp.main()
    }
}

struct BuilderApp: App {
    @NSApplicationDelegateAdaptor(BuilderAppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("GB App Builder", id: "builder") {
            BuilderView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open ROM…") { NotificationCenter.default.post(name: .openROM, object: nil) }
                    .keyboardShortcut("o")
            }
        }
        Settings {
            BuilderSettingsView()
        }
    }
}

final class BuilderAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// ROMs dropped on the Dock icon or opened with "Open With".
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: .openROM, object: url)
            }
        }
    }
}

enum CommandLineBuild {
    static let usage = """
    Usage: "GB App Builder" --rom <file.gb|.gbc|.gba|.zip> [options]

      --out <folder>      where the app goes (default: the builder's setting, \(BuilderSettings.shared.outputFolder))
      --name <name>       app name (default: the No-Intro name without region tags)
      --icon <image>      icon image (default: libretro box art, else mGBA's system icon)
      --no-boxart         do not download box art
      --sign <identity>   codesigning identity, "-" for ad hoc (default: the builder's setting)
      --bios <folder>     BIOS folder (default: the builder's setting, else the bundled BIOS)
      --set key=value     an mGBA default for the app (repeatable), e.g. --set gb.model=CGB
    """

    static func run(_ arguments: [String]) -> Int32 {
        var options: [String: String] = [:]
        var sets: [String: String] = [:]
        var flags = Set<String>()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--no-boxart", "--help":
                flags.insert(argument)
            case "--set":
                index += 1
                if index < arguments.count, let eq = arguments[index].firstIndex(of: "=") {
                    sets[String(arguments[index][..<eq])] = String(arguments[index][arguments[index].index(after: eq)...])
                }
            default:
                if argument.hasPrefix("--"), index + 1 < arguments.count {
                    options[argument] = arguments[index + 1]
                    index += 1
                } else if argument.hasPrefix("-") {
                    // AppKit's own arguments (-NSDocumentRevisionsDebugMode YES, ...)
                    index += 1
                }
            }
            index += 1
        }
        if flags.contains("--help") || options["--rom"] == nil {
            print(usage)
            return flags.contains("--help") ? 0 : 2
        }
        let settings = BuilderSettings.shared
        do {
            let romURL = URL(fileURLWithPath: (options["--rom"]! as NSString).expandingTildeInPath)
            let rom = try ROMInspector.open(romURL)
            let datName = DatIndex.shared.name(crc: rom.crc32, system: rom.system)
            print("ROM: \(rom.fileName) · \(rom.systemName) · CRC \(rom.crc32) · header \(rom.headerTitle) \(rom.gameCode)")
            print("No-Intro: \(datName ?? "no match")")
            let name = options["--name"] ?? (datName ?? romURL.deletingPathExtension().lastPathComponent).cleanGameTitle

            var icon: NSImage?
            if let path = options["--icon"] {
                icon = NSImage(contentsOfFile: (path as NSString).expandingTildeInPath)
            } else if !flags.contains("--no-boxart") {
                let names = [datName, romURL.deletingPathExtension().lastPathComponent, rom.baseName].compactMap { $0 }
                let semaphore = DispatchSemaphore(value: 0)
                var found: (NSImage, URL)?
                Task.detached {
                    found = await BoxArt.fetch(system: rom.libretroSystem, names: names)
                    semaphore.signal()
                }
                semaphore.wait()
                if let found {
                    icon = found.0
                    print("Icon: \(found.1.absoluteString.removingPercentEncoding ?? found.1.absoluteString)")
                } else {
                    print("Icon: no box art found, mGBA's system icon")
                }
            }

            var defaults: [String: String] = ["videoScale": "3"]
            defaults.merge(sets) { $1 }
            if defaults["savegamePath"] == nil, !settings.saveFolder.isEmpty { defaults["savegamePath"] = settings.saveFolder }
            let request = BuildRequest(
                rom: rom, appName: name, romName: datName, icon: icon,
                outputFolder: options["--out"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) } ?? settings.outputURL,
                bundleIDPrefix: settings.bundleIDPrefix,
                signingIdentity: options["--sign"] ?? settings.identity,
                biosFolder: options["--bios"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) } ?? settings.biosURL,
                defaults: defaults)
            let result = try AppAssembler.build(request) { print($0) }
            for warning in result.warnings { print("Warning: \(warning)") }
            print(result.appURL.path)
            return 0
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}
