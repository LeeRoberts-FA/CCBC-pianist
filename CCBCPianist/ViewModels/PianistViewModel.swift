import Foundation
import Combine
import CoreMIDI

@MainActor
final class PianistViewModel: ObservableObject {
    @Published var status = "Ready for the four-note test."
    @Published var pianoStatus = ""
    @Published var midiOutputs: [MIDIDestination] = []
    @Published var selectedMIDI = -1  // -1 = local sampled piano

    @Published var records: [HymnRecord] = []
    @Published var currentTitle = "Original four-note test"
    @Published var selectedHymnID: UUID?
    @Published var speed = 1.0
    @Published var isPlaying = false
    @Published var isPaused = false

    @Published var models: [String] = []
    @Published var selectedModel = ""
    @Published var aiQuestion = "How should a traditional Baptist hymn be prepared for congregational singing?"
    @Published var aiResponse = "AI is optional and cannot control live piano playback."
    @Published var isAsking = false

    private let sound: PianoAudio
    private let midi: KronosMIDI
    private let engine: PlaybackEngine
    private let library = HymnLibrary()
    private let ollama = OllamaService()
    private var music: [MIDIEvent] = MIDIFileDecoder.fourNoteTest()

    var isTest: Bool { selectedHymnID == nil }
    var selectedRecord: HymnRecord? { records.first { $0.id == selectedHymnID } }
    var canPlay: Bool { !isPlaying && (isTest || selectedRecord?.approved == true) }

    init() {
        let sound = PianoAudio()
        let midi = KronosMIDI()
        self.sound = sound
        self.midi = midi
        self.engine = PlaybackEngine(sound: sound, midi: midi)
        self.pianoStatus = sound.description
        self.records = library.records
        refreshMIDI()
    }

    func refreshMIDI() {
        midiOutputs = midi.destinations()
        if selectedMIDI != -1 && !midiOutputs.contains(where: { $0.id == selectedMIDI }) {
            selectedMIDI = -1
        }
        if selectedMIDI == -1,
           let kronos = midiOutputs.first(where: {
               $0.name.localizedCaseInsensitiveContains("KRONOS")
           }) {
            selectedMIDI = kronos.id
        }
        status = midiOutputs.isEmpty
            ? "No USB-MIDI destination detected. You may use the Mac sampled piano."
            : "Detected \(midiOutputs.count) MIDI destination(s)."
    }

    func loadPianoBank(_ url: URL) {
        stop()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        sound.loadBank(url)
        pianoStatus = sound.description
        status = sound.isReady ? "Sampled piano ready." : "Unable to load piano bank."
    }

    func useFourNoteTest() {
        stop()
        selectedHymnID = nil
        currentTitle = "Original four-note test"
        music = MIDIFileDecoder.fourNoteTest()
        status = "Original four-note C–E–G–C test selected."
    }

    func importHymn(_ url: URL, number: String, title: String) {
        stop()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let events = try MIDIFileDecoder.parse(data)
            let record = try library.add(
                midiURL: url,
                number: number,
                title: title,
                eventCount: events.filter(\.isNoteOn).count
            )
            records = library.records
            music = events
            selectedHymnID = record.id
            currentTitle = "#\(record.number) \(record.title)"
            status = "Imported \(record.noteCount) notes. Review against the score before approving."
        } catch {
            status = "MIDI import error: \(error.localizedDescription)"
        }
    }

    func chooseHymn(_ record: HymnRecord) {
        stop()
        do {
            let file = library.fileURL(for: record)
            let loaded = try MIDIFileDecoder.parse(Data(contentsOf: file))
            music = loaded
            selectedHymnID = record.id
            currentTitle = "#\(record.number) \(record.title)"
            status = record.approved
                ? "Arrangement approved by user; ready for controlled playback."
                : "Arrangement awaits score review and approval."
        } catch {
            status = "Cannot open arrangement: \(error.localizedDescription)"
        }
    }

    func setApproval(_ id: UUID, to approved: Bool) {
        stop()
        do {
            try library.setApproved(id, approved: approved)
            records = library.records
            status = approved
                ? "Arrangement manually approved. This does not independently verify musical accuracy."
                : "Approval revoked; this imported arrangement cannot play."
        } catch {
            status = "Cannot update approval: \(error.localizedDescription)"
        }
    }

    func play() {
        guard !isPlaying else { return }
        if !isTest && selectedRecord?.approved != true {
            status = HymnLibraryError.notApproved.localizedDescription
            return
        }

        let target: MIDIEndpointRef?
        if selectedMIDI == -1 {
            guard sound.isReady else {
                status = HymnLibraryError.pianoUnavailable.localizedDescription
                return
            }
            target = nil
        } else {
            guard let item = midiOutputs.first(where: { $0.id == selectedMIDI }),
                  midi.destinations().contains(where: { $0.id == selectedMIDI }) else {
                status = HymnLibraryError.disconnectedMIDI.localizedDescription
                return
            }
            target = item.endpoint
        }

        isPlaying = true
        isPaused = false
        status = "Playing \(currentTitle)…"
        engine.start(
            events: music,
            speed: speed,
            destination: target,
            onFinished: { [weak self] in
                guard let self = self else { return }
                self.isPlaying = false
                self.isPaused = false
                self.status = "Playback completed."
            },
            onError: { [weak self] text in
                guard let self = self else { return }
                self.isPlaying = false
                self.isPaused = false
                self.status = text
            }
        )
    }

    func pauseResume() {
        guard isPlaying else { return }
        if isPaused {
            engine.resume()
            isPaused = false
            status = "Resumed. Notes held during the pause are not restored."
        } else {
            engine.pause()
            isPaused = true
            status = "Paused. Held notes released."
        }
    }

    func stop() {
        engine.stop()
        isPlaying = false
        isPaused = false
        status = "Stopped. Sustain off and all-notes-off sent."
    }

    func checkOllama() {
        Task {
            do {
                let found = try await ollama.models()
                models = found
                if !found.contains(selectedModel) {
                    selectedModel = found.first ?? ""
                }
                aiResponse = found.isEmpty
                    ? "Ollama is running but no model is installed."
                    : "Ollama connected. Installed models: \(found.joined(separator: ", "))"
            } catch {
                aiResponse = "Ollama isn't available. Piano playback still works. \(error.localizedDescription)"
            }
        }
    }

    func askAI() {
        guard !selectedModel.isEmpty, !aiQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            aiResponse = "Choose an installed Ollama model and enter a question."
            return
        }
        guard !isPlaying else {
            aiResponse = "Wait until playback ends before running the AI assistant."
            return
        }
        isAsking = true
        aiResponse = "Preparing an answer locally…"
        let question = aiQuestion
        let name = selectedModel
        Task {
            defer { isAsking = false }
            do {
                aiResponse = try await ollama.ask(model: name, question: question)
            } catch {
                aiResponse = "Local model request failed: \(error.localizedDescription)"
            }
        }
    }
}
