import Foundation
import SwiftUI

/// The builder's own preferences (UserDefaults).
final class BuilderSettings: ObservableObject {
    static let shared = BuilderSettings()
    private let defaults = UserDefaults.standard

    @AppStorage("outputFolder") var outputFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/mGBA Games", isDirectory: true).path
    @AppStorage("romLibrary") var romLibrary = "/Volumes/Shared/RETRO_GAMES/ROMs"
    /// Empty = the BIOS files bundled with the builder.
    @AppStorage("biosFolder") var biosFolder = ""
    /// Empty = ad hoc.
    @AppStorage("signingIdentity") var signingIdentity = ""
    @AppStorage("bundleIDPrefix") var bundleIDPrefix = "com.windholm.gb-appbuilder.game"
    /// Empty = each game's own folder in ~/Library/Application Support/mGBA Games/<name>/saves.
    @AppStorage("saveFolder") var saveFolder = ""
    @AppStorage("fetchBoxArt") var fetchBoxArt = true

    var outputURL: URL { URL(fileURLWithPath: (outputFolder as NSString).expandingTildeInPath, isDirectory: true) }
    var biosURL: URL? { biosFolder.isEmpty ? nil : URL(fileURLWithPath: (biosFolder as NSString).expandingTildeInPath, isDirectory: true) }
    var identity: String { signingIdentity.isEmpty ? "-" : signingIdentity }

    init() {
        // First run: sign with a Developer ID when there is one.
        if defaults.object(forKey: "signingIdentity") == nil,
           let developerID = AppAssembler.signingIdentities().first(where: { $0.hasPrefix("Developer ID Application") }) {
            signingIdentity = developerID
        }
    }
}

struct BuilderSettingsView: View {
    @ObservedObject var settings = BuilderSettings.shared
    @State private var identities: [String] = []

    var body: some View {
        Form {
            Section("Folders") {
                folderRow("Built apps", value: $settings.outputFolder)
                folderRow("ROM library", value: $settings.romLibrary)
                folderRow("BIOS files", value: $settings.biosFolder, placeholder: "Bundled with the builder")
                folderRow("Battery saves", value: $settings.saveFolder, placeholder: "Each game's folder in Application Support")
            }
            Section("Signing") {
                Picker("Identity", selection: $settings.signingIdentity) {
                    Text("Ad hoc (this Mac only)").tag("")
                    ForEach(identities, id: \.self) { Text($0).tag($0) }
                }
                TextField("Bundle ID prefix", text: $settings.bundleIDPrefix)
            }
            Section("Icons") {
                Toggle("Download box art from the libretro thumbnail server", isOn: $settings.fetchBoxArt)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 420)
        .onAppear { identities = AppAssembler.signingIdentities() }
    }

    private func folderRow(_ title: String, value: Binding<String>, placeholder: String = "") -> some View {
        LabeledContent(title) {
            HStack {
                Text(value.wrappedValue.isEmpty ? placeholder : value.wrappedValue)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url { value.wrappedValue = url.path }
                }
                if !placeholder.isEmpty && !value.wrappedValue.isEmpty {
                    Button("Default") { value.wrappedValue = "" }
                }
            }
        }
    }
}
