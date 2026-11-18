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
    @Published var ollamaEndpoint = OllamaConnection.savedEndpoint()
    @Published var ollamaToken = OllamaConnection.loadToken(for: OllamaConnection.savedEndpoint())
    @Published var ollamaConnectionStatus = "Local Ollama by default; remote HTTPS or an SSH tunnel also supported."
    @Published var isCheckingOllama = false
    @Published var aiQuestion = "How should a traditional Baptist hymn be prepared for congregational singing?"
    @Published var aiResponse = "AI is optional and cannot control live piano playback."
    @Published var isAsking = false

    private let sound: PianoAudio
    private let midi: KronosMIDI
    private let engine: PlaybackEngine
    private let library = HymnLibrary()
    private let ollama = OllamaService()
    private var aiTask: Task<Void, Never>?
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

    @discardableResult
    func saveOllamaConnection() -> Bool {
        do {
            let endpoint = try OllamaConnection.validate(ollamaEndpoint).absoluteString
            let token = ollamaToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let previousEndpoint = OllamaConnection.savedEndpoint()
            let previousToken = OllamaConnection.loadToken(for: previousEndpoint)
            let changed = endpoint != previousEndpoint || token != previousToken

            if changed {
                try OllamaConnection.save(endpoint: endpoint, token: token)
                // A different server or credential must be checked before use.
                selectedModel = ""
                models = []
                ollamaConnectionStatus = "Connection saved. Detect models on the selected server."
                aiResponse = "Connection settings changed. Detect models to continue."
            } else {
                // Saving the same connection must not discard discovery or
                // the user's model selection, or overwrite a completed answer.
                ollamaConnectionStatus = models.isEmpty
                    ? "Connection saved. Detect models to continue."
                    : "Connection saved. \(models.count) detected model(s) retained."
            }
            return true
        } catch {
            ollamaConnectionStatus = "Connection settings error: \(error.localizedDescription)"
            return false
        }
    }

    func checkOllama() {
        guard !isCheckingOllama, !isAsking else { return }
        guard saveOllamaConnection() else { return }
        isCheckingOllama = true
        aiResponse = "Connecting to the selected Ollama server…"
        let endpoint = OllamaConnection.savedEndpoint()
        let token = OllamaConnection.loadToken(for: endpoint)
        let previousModel = selectedModel
        Task {
            defer { isCheckingOllama = false }
            do {
                let found = try await ollama.models(endpoint: endpoint, token: token)
                selectedModel = found.contains(previousModel) ? previousModel : (found.first ?? "")
                models = found
                ollamaConnectionStatus = "Connected to Ollama. \(found.count) model(s) available."
                aiResponse = found.isEmpty
                    ? "Server connected but no model is installed or available."
                    : "Connected. Choose a model and ask a question."
            } catch {
                selectedModel = ""
                models = []
                ollamaConnectionStatus = "Unable to connect: \(error.localizedDescription)"
                aiResponse = ollamaConnectionStatus + " The piano works independently."
            }
        }
    }

    func askAI() {
        guard !isAsking, !isCheckingOllama, !selectedModel.isEmpty,
              models.contains(selectedModel),
              !aiQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            aiResponse = "Choose an installed Ollama model and enter a question."
            return
        }
        guard !isPlaying else {
            aiResponse = "Wait until playback ends before running the AI assistant."
            return
        }

        let endpoint = OllamaConnection.savedEndpoint()
        let token = OllamaConnection.loadToken(for: endpoint)
        guard (try? OllamaConnection.validate(ollamaEndpoint).absoluteString) == endpoint,
              ollamaToken.trimmingCharacters(in: .whitespacesAndNewlines) == token else {
            aiResponse = "Connection settings changed. Save the connection and detect models before asking."
            return
        }

        isAsking = true
        aiResponse = "Connecting to model… The first response can take time while the server loads it."
        let question = aiQuestion
        let name = selectedModel
        aiTask = Task {
            defer {
                isAsking = false
                aiTask = nil
            }
            do {
                let final = try await ollama.ask(
                    endpoint: endpoint,
                    token: token,
                    model: name,
                    question: question
                ) { [weak self] response in
                    self?.aiResponse = response
                }
                aiResponse = final
            } catch is CancellationError {
                aiResponse = "AI request cancelled."
            } catch {
                aiResponse = "AI request failed: \(error.localizedDescription) For an 8 GB Mac, try an external inference server or smaller model."
            }
        }
    }

    func cancelAI() {
        aiTask?.cancel()
        aiTask = nil
        isAsking = false
        aiResponse = "AI request cancelled."
    }
}
