import Foundation

struct HymnRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var number: String
    var title: String
    var midiFilename: String
    var noteCount: Int
    var approved: Bool
    var importedAt: Date

    init(number: String, title: String, midiFilename: String, noteCount: Int) {
        self.id = UUID()
        self.number = number
        self.title = title
        self.midiFilename = midiFilename
        self.noteCount = noteCount
        self.approved = false
        self.importedAt = Date()
    }
}

enum HymnLibraryError: LocalizedError {
    case missingMetadata
    case noSelection
    case notApproved
    case missingFile
    case pianoUnavailable
    case disconnectedMIDI

    var errorDescription: String? {
        switch self {
        case .missingMetadata: return "Enter a hymn number and title before import."
        case .noSelection: return "Choose an arrangement or the original four-note test."
        case .notApproved: return "An imported arrangement must be reviewed and approved before playback."
        case .missingFile: return "The saved MIDI file could not be found."
        case .pianoUnavailable: return "No sampled piano bank is loaded. Load a .sf2/.dls bank or choose a MIDI instrument."
        case .disconnectedMIDI: return "The selected MIDI destination is disconnected. Refresh MIDI devices."
        }
    }
}

@MainActor
final class HymnLibrary {
    private let directory: URL
    private let indexURL: URL
    private let filesURL: URL

    private(set) var records: [HymnRecord] = []

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        directory = support.appendingPathComponent("CCBCPianist", isDirectory: true)
        filesURL = directory.appendingPathComponent("Hymns", isDirectory: true)
        indexURL = directory.appendingPathComponent("library.json")

        try? FileManager.default.createDirectory(
            at: filesURL, withIntermediateDirectories: true
        )
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([HymnRecord].self, from: data) {
            records = saved
        }
    }

    private func save() throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: indexURL, options: .atomic)
    }

    func add(midiURL: URL, number: String, title: String, eventCount: Int) throws -> HymnRecord {
        let n = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !t.isEmpty else { throw HymnLibraryError.missingMetadata }

        let name = UUID().uuidString + ".mid"
        let dest = filesURL.appendingPathComponent(name)
        try FileManager.default.copyItem(at: midiURL, to: dest)

        let record = HymnRecord(number: n, title: t, midiFilename: name, noteCount: eventCount)
        records.append(record)
        do {
            try save()
        } catch {
            records.removeAll { $0.id == record.id }
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
        return record
    }

    func setApproved(_ id: UUID, approved: Bool) throws {
        guard let i = records.firstIndex(where: { $0.id == id }) else {
            throw HymnLibraryError.noSelection
        }
        let previous = records[i].approved
        records[i].approved = approved
        do { try save() } catch {
            records[i].approved = previous
            throw error
        }
    }

    func fileURL(for record: HymnRecord) -> URL {
        filesURL.appendingPathComponent(record.midiFilename)
    }
}
