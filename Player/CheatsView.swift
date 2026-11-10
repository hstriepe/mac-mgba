import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// mGBA's cheat sets for this game (GameShark, Action Replay, CodeBreaker, Game Genie codes),
/// kept in `<data folder>/<rom>.cheats` in mGBA's own format.
final class CheatsModel: ObservableObject {
    struct Entry: Identifiable {
        let id: Int
        let name: String
        let enabled: Bool
    }

    let session: EmulatorSession
    @Published var entries: [Entry] = []
    @Published var newName = ""
    @Published var newCodes = ""
    @Published var error: String?

    init(session: EmulatorSession) {
        self.session = session
        reload()
    }

    func reload() {
        entries = session.withCore { core in
            (0..<gbp_cheats_count(core)).map { index in
                var name = [CChar](repeating: 0, count: 256)
                gbp_cheats_name(core, index, &name, name.count)
                let text = String(cString: name)
                return Entry(id: index, name: text.isEmpty ? "Cheat \(index + 1)" : text, enabled: gbp_cheats_enabled(core, index))
            }
        }
    }

    func setEnabled(_ entry: Entry, _ enabled: Bool) {
        session.withCore { gbp_cheats_set_enabled($0, entry.id, enabled) }
        commit()
    }

    func remove(_ entry: Entry) {
        session.withCore { gbp_cheats_remove($0, entry.id) }
        commit()
    }

    func add() {
        let name = newName.isEmpty ? "Cheat \(entries.count + 1)" : newName
        let ok = session.withCore { gbp_cheats_add($0, name, newCodes) }
        if ok {
            newName = ""
            newCodes = ""
            error = nil
            commit()
        } else {
            error = "None of these lines is a code mGBA understands for this game."
        }
    }

    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cheats"), .plainText].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if session.withCore({ gbp_cheats_load($0, url.path) }) {
            commit()
        } else {
            error = "This file holds no cheats mGBA can read."
        }
    }

    private func commit() {
        session.saveCheats()
        reload()
    }
}

struct CheatsView: View {
    @ObservedObject var model: CheatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach(model.entries) { entry in
                    HStack {
                        Toggle(entry.name, isOn: Binding(get: { entry.enabled }, set: { model.setEnabled(entry, $0) }))
                        Spacer()
                        Button(role: .destructive) { model.remove(entry) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 140)
            .overlay {
                if model.entries.isEmpty { Text("No cheats yet").foregroundStyle(.secondary) }
            }
            GroupBox("Add codes") {
                VStack(alignment: .leading) {
                    TextField("Name", text: $model.newName)
                    TextEditor(text: $model.newCodes)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
                    HStack {
                        Text("One code per line: GameShark, Action Replay, CodeBreaker or Game Genie.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Import File…") { model.importFile() }
                        Button("Add") { model.add() }.disabled(model.newCodes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(4)
            }
            if let error = model.error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 420)
    }
}
