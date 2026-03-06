import Foundation

struct DictationEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let date: Date
    let durationSeconds: Double

    init(text: String, durationSeconds: Double) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.durationSeconds = durationSeconds
    }
}

class HistoryStore: ObservableObject {
    @Published var entries: [DictationEntry] = []

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("OpenWhispr")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    init() {
        load()
    }

    func add(text: String, durationSeconds: Double) {
        let entry = DictationEntry(text: text, durationSeconds: durationSeconds)
        entries.insert(entry, at: 0)
        // Keep last 500
        if entries.count > 500 {
            entries = Array(entries.prefix(500))
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    func delete(_ entry: DictationEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([DictationEntry].self, from: data)
        } catch {
            print("Failed to load history: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
}
