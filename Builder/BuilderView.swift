import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BuilderModel: ObservableObject {
    @Published var rom: ROMInfo?
    @Published var datName: String?
    @Published var appName = ""
    @Published var icon: NSImage?
    @Published var iconSource = ""
    @Published var fetchingIcon = false
    @Published var error: String?
    @Published var building = false
    @Published var log: [String] = []
    @Published var result: BuildResult?

    // Defaults written into the app (mGBA config keys)
    @Published var model = ""            // GB model, "" = autodetect
    @Published var frameSize = 3
    @Published var showBIOSIntro = true
    @Published var interframeBlending = false
    @Published var sgbBorders = true
    @Published var customSaveFolder = ""

    let settings = BuilderSettings.shared

    static let openTypes: [UTType] = ["gb", "gbc", "gba", "sgb", "zip"].compactMap { UTType(filenameExtension: $0) }

    func choose() {
        let panel = NSOpenPanel()
        panel.title = "Open a Game Boy, Game Boy Color or Game Boy Advance ROM"
        panel.allowedContentTypes = Self.openTypes
        let library = URL(fileURLWithPath: settings.romLibrary, isDirectory: true)
        if FileManager.default.fileExists(atPath: library.path) { panel.directoryURL = library }
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        error = nil
        result = nil
        log = []
        do {
            let rom = try ROMInspector.open(url)
            self.rom = rom
            datName = DatIndex.shared.name(crc: rom.crc32, system: rom.system)
            let fileName = url.deletingPathExtension().lastPathComponent
            appName = (datName ?? fileName).cleanGameTitle
            if appName.isEmpty { appName = rom.headerTitle.capitalized }
            customSaveFolder = settings.saveFolder
            icon = nil
            iconSource = ""
            if settings.fetchBoxArt { fetchIcon() } else { useDefaultIcon() }
        } catch {
            rom = nil
            self.error = error.localizedDescription
        }
    }

    func fetchIcon() {
        guard let rom else { return }
        let names = [datName, rom.sourceURL.deletingPathExtension().lastPathComponent, rom.baseName].compactMap { $0 }
        fetchingIcon = true
        Task {
            let found = await BoxArt.fetch(system: rom.libretroSystem, names: names)
            fetchingIcon = false
            guard self.rom == rom else { return }
            if let (image, url) = found {
                icon = image
                iconSource = url.pathComponents.dropLast().last == "Named_Titles" ? "Title screen (libretro)" : "Box art (libretro)"
            } else {
                useDefaultIcon()
                iconSource = "No box art found: mGBA's \(rom.system.uppercased()) icon"
            }
        }
    }

    func useDefaultIcon() {
        guard let rom else { return }
        icon = IconMaker.defaultImage(system: rom.system)
        iconSource = "mGBA's \(rom.system.uppercased()) icon"
    }

    func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        icon = image
        iconSource = url.lastPathComponent
    }

    func setIcon(from url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        icon = image
        iconSource = url.lastPathComponent
    }

    func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { customSaveFolder = url.path }
    }

    var defaults: [String: String] {
        var values: [String: String] = [
            "videoScale": String(frameSize),
            "skipBios": showBIOSIntro ? "0" : "1",
            "interframeBlending": interframeBlending ? "1" : "0",
        ]
        if rom?.system != "gba" {
            values["sgb.borders"] = sgbBorders ? "1" : "0"
            if !model.isEmpty {
                for key in ["gb.model", "sgb.model", "cgb.model", "cgb.hybridModel", "cgb.sgbModel"] { values[key] = model }
            }
        }
        if !customSaveFolder.isEmpty { values["savegamePath"] = customSaveFolder }
        return values
    }

    var targetURL: URL? {
        guard let rom else { return nil }
        return AppAssembler.appURL(for: request(rom))
    }

    private func request(_ rom: ROMInfo) -> BuildRequest {
        BuildRequest(rom: rom, appName: appName.trimmingCharacters(in: .whitespaces), romName: datName, icon: icon,
                     outputFolder: settings.outputURL, bundleIDPrefix: settings.bundleIDPrefix,
                     signingIdentity: settings.identity, biosFolder: settings.biosURL, defaults: defaults)
    }

    func build() {
        guard let rom, !appName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let target = targetURL, FileManager.default.fileExists(atPath: target.path) {
            let alert = NSAlert()
            alert.messageText = "“\(target.lastPathComponent)” already exists."
            alert.informativeText = "The old app goes to the Trash. Its save and settings stay in Application Support and are used by the new one."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let request = request(rom)
        building = true
        error = nil
        result = nil
        log = []
        Task.detached {
            do {
                let result = try AppAssembler.build(request) { line in
                    Task { @MainActor in self.log.append(line) }
                }
                await MainActor.run {
                    self.result = result
                    self.building = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.building = false
                }
            }
        }
    }
}

struct BuilderView: View {
    @StateObject private var model = BuilderModel()
    @State private var dropTargeted = false

    var body: some View {
        Group {
            if let rom = model.rom {
                details(rom)
            } else {
                dropZone
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.open(url) }
            }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openROM)) { note in
            if let url = note.object as? URL { model.open(url) } else { model.choose() }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 128, height: 128)
            Text("Drop a Game Boy, Game Boy Color or Game Boy Advance ROM here").font(.title3)
            Text(".gb, .gbc, .gba or a .zip holding one").foregroundStyle(.secondary)
            Button("Open ROM…") { model.choose() }.keyboardShortcut("o")
            if let error = model.error { Text(error).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(dropTargeted ? Color.accentColor : .secondary.opacity(0.3),
                                                                      style: StrokeStyle(lineWidth: 2, dash: [8])).padding(20))
    }

    private func details(_ rom: ROMInfo) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                    if let icon = model.icon {
                        Image(nsImage: IconMaker.squareImage(icon, size: 512)).resizable().interpolation(.high).padding(8)
                    }
                    if model.fetchingIcon { ProgressView() }
                }
                .frame(width: 200, height: 200)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in model.setIcon(from: url) } }
                    }
                    return true
                }
                Text(model.iconSource).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Button("Choose…") { model.chooseIcon() }
                    Button("Box Art") { model.fetchIcon() }
                    Button("Default") { model.useDefaultIcon() }
                }
                .controlSize(.small)
            }
            .frame(width: 220)

            Form {
                Section("Game") {
                    TextField("App name", text: $model.appName)
                    LabeledContent("System", value: rom.systemName)
                    LabeledContent("No-Intro", value: model.datName ?? "No DAT match (CRC \(rom.crc32))")
                    LabeledContent("Header", value: [rom.headerTitle, rom.gameCode].filter { !$0.isEmpty }.joined(separator: " · "))
                    LabeledContent("File", value: rom.fileName)
                    LabeledContent("BIOS", value: rom.biosFiles.values.sorted().joined(separator: ", "))
                    if !rom.otherFilesInArchive.isEmpty {
                        LabeledContent("Not used", value: rom.otherFilesInArchive.joined(separator: ", "))
                    }
                }
                Section("Defaults (the app's Settings can change them)") {
                    Picker("Frame size", selection: $model.frameSize) {
                        ForEach(1...6, id: \.self) { Text("\($0)×").tag($0) }
                    }
                    Toggle("Show the BIOS boot animation", isOn: $model.showBIOSIntro)
                    Toggle("Interframe blending", isOn: $model.interframeBlending)
                    if rom.system != "gba" {
                        Picker("Game Boy model", selection: $model.model) {
                            Text("Autodetect").tag("")
                            Text("Game Boy (DMG)").tag("DMG")
                            Text("Super Game Boy (SGB)").tag("SGB")
                            Text("Game Boy Color (CGB)").tag("CGB")
                            Text("Game Boy Advance (AGB)").tag("AGB")
                        }
                        Toggle("Super Game Boy borders", isOn: $model.sgbBorders)
                    }
                    LabeledContent("Battery saves") {
                        HStack {
                            Text(model.customSaveFolder.isEmpty ? "~/Library/Application Support/mGBA Games/\(GamePaths.sanitize(model.appName))/saves" : model.customSaveFolder)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Button("Choose…") { model.chooseSaveFolder() }
                            if !model.customSaveFolder.isEmpty { Button("Default") { model.customSaveFolder = "" } }
                        }
                    }
                }
                Section {
                    LabeledContent("Builds", value: model.targetURL?.path ?? "")
                    HStack {
                        Button("Open Another…") { model.choose() }
                        Spacer()
                        if model.building { ProgressView().controlSize(.small) }
                        Button("Build App") { model.build() }
                            .keyboardShortcut("b")
                            .buttonStyle(.borderedProminent)
                            .disabled(model.building || model.appName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                    if let result = model.result {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Built \(result.appURL.lastPathComponent)").bold()
                            ForEach(result.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                            HStack {
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.appURL]) }
                                Button("Open") { NSWorkspace.shared.open(result.appURL) }
                            }
                        }
                    } else if !model.log.isEmpty {
                        Text(model.log.last ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding()
    }
}

extension Notification.Name {
    static let openROM = Notification.Name("GBAppBuilderOpenROM")
}
