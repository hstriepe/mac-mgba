import Foundation

/// Finds and downloads a game's manual from archive.org's Nintendo manual packs, whose PDFs are named by
/// No-Intro name ("Advance Wars (USA) (Rev 1).pdf"). The file index of the three items is cached for 30 days;
/// downloaded PDFs are cached too.
enum ManualFinder {
    /// archive.org items, searched in this order (a GBC game may be filed with the Game Boy manuals and vice versa).
    static let items: [String: [String]] = [
        "gb": ["NintendoGameBoyManuals", "NintendoGameBoyColorManuals"],
        "gbc": ["NintendoGameBoyColorManuals", "NintendoGameBoyManuals"],
        "gba": ["NintendoGameBoyAdvanceManuals"],
    ]

    struct Entry: Codable, Equatable {
        /// archive.org item identifier.
        var item: String
        /// File name without ".pdf": the No-Intro name.
        var name: String
        var size: Int

        var url: URL? {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "archive.org"
            components.path = "/download/\(item)/\(name).pdf"
            return components.url
        }
    }

    struct Found {
        var entry: Entry
        var file: URL
        /// True when only the title matched (another region or revision).
        var approximate: Bool
    }

    private static let maxIndexAge: TimeInterval = 30 * 24 * 3600

    static var cacheFolder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")
        return caches.appendingPathComponent("com.windholm.gb-appbuilder/Manuals", isDirectory: true)
    }

    /// Finds the manual for the first of `names` that matches (exact No-Intro name first, then the same title
    /// with other tags) and downloads it. nil when there is none, or when offline with nothing cached.
    static func find(system: String, names: [String]) async -> Found? {
        let entries = await index(items: items[system] ?? [])
        guard !entries.isEmpty else { return nil }
        var match: (Entry, Bool)?
        for name in names {
            if let exact = entries.first(where: { $0.name == name }) {
                match = (exact, false)
                break
            }
        }
        if match == nil {
            for name in names {
                let title = name.cleanGameTitle.lowercased()
                guard !title.isEmpty else { continue }
                let candidates = entries.filter { $0.name.cleanGameTitle.lowercased() == title }
                // Prefer the USA or world release, as the ROM library is mostly those.
                if let best = candidates.first(where: { $0.name.contains("USA") || $0.name.contains("World") }) ?? candidates.first {
                    match = (best, true)
                    break
                }
            }
        }
        guard let (entry, approximate) = match, let file = await download(entry) else { return nil }
        return Found(entry: entry, file: file, approximate: approximate)
    }

    /// The PDFs of the given items (cached file index, refreshed after 30 days; a stale cache is used when offline).
    static func index(items: [String]) async -> [Entry] {
        var result: [Entry] = []
        for item in items {
            result += await index(item: item)
        }
        return result
    }

    private static func index(item: String) async -> [Entry] {
        let cache = cacheFolder.appendingPathComponent("\(item).json")
        let cached = (try? Data(contentsOf: cache)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) }
        let age = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { Date().timeIntervalSince($0) } ?? .infinity
        if let cached, age < maxIndexAge { return cached }

        guard let url = URL(string: "https://archive.org/metadata/\(item)/files") else { return cached ?? [] }
        do {
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("GB App Builder", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return cached ?? [] }
            struct Listing: Decodable {
                struct File: Decodable {
                    var name: String
                    var size: String?
                }
                var result: [File]
            }
            let listing = try JSONDecoder().decode(Listing.self, from: data)
            // The scans themselves; archive.org's derived "<name>_text.pdf" (OCR) copies are left out.
            let entries = listing.result
                .filter { $0.name.hasSuffix(".pdf") && !$0.name.hasSuffix("_text.pdf") && !$0.name.contains("/") }
                .map { Entry(item: item, name: String($0.name.dropLast(4)), size: Int($0.size ?? "") ?? 0) }
            try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
            try? JSONEncoder().encode(entries).write(to: cache)
            return entries
        } catch {
            return cached ?? []
        }
    }

    /// Downloads the PDF into the cache (once) and returns the cached file.
    static func download(_ entry: Entry) async -> URL? {
        let folder = cacheFolder.appendingPathComponent(entry.item, isDirectory: true)
        let file = folder.appendingPathComponent(GamePaths.sanitize(entry.name) + ".pdf")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let url = entry.url else { return nil }
        do {
            var request = URLRequest(url: url, timeoutInterval: 120)
            request.setValue("GB App Builder", forHTTPHeaderField: "User-Agent")
            let (temporary, response) = try await URLSession.shared.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            // A PDF starts with "%PDF".
            let handle = try FileHandle(forReadingFrom: temporary)
            let head = try handle.read(upToCount: 4)
            try handle.close()
            guard head == Data("%PDF".utf8) else { return nil }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: temporary, to: file)
            return file
        } catch {
            return nil
        }
    }
}
