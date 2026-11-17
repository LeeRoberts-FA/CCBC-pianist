import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: PianistViewModel

    @State private var importMIDI = false
    @State private var importBank = false
    @State private var hymnNumber = ""
    @State private var hymnTitle = ""
    @State private var recordPendingApproval: UUID?
    @State private var showApprovalConfirmation = false

    private var midiTypes: [UTType] {
        [UTType(filenameExtension: "mid") ?? .data,
         UTType(filenameExtension: "midi") ?? .data]
    }

    private var pianoTypes: [UTType] {
        [UTType(filenameExtension: "sf2") ?? .data,
         UTType(filenameExtension: "dls") ?? .data]
    }

    var body: some View {
        TabView {
            performance
                .tabItem { Label("Pianist", systemImage: "pianokeys") }

            library
                .tabItem { Label("Hymnal Library", systemImage: "books.vertical") }

            assistant
                .tabItem { Label("Ollama Assistant", systemImage: "brain") }

            setup
                .tabItem { Label("Setup & Safety", systemImage: "gearshape") }
        }
        .frame(minWidth: 780, minHeight: 640)
        .tint(Color(red: 0.62, green: 0.18, blue: 0.21))
        .fileImporter(isPresented: $importMIDI, allowedContentTypes: midiTypes) { result in
            switch result {
            case .success(let url):
                model.importHymn(url, number: hymnNumber, title: hymnTitle)
            case .failure(let error):
                model.status = "Import cancelled or failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $importBank, allowedContentTypes: pianoTypes) { result in
            switch result {
            case .success(let url): model.loadPianoBank(url)
            case .failure(let error):
                model.status = "Sound bank selection failed: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "Approve this arrangement after checking it against the printed score?",
            isPresented: $showApprovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("I have reviewed the score — Approve") {
                if let id = recordPendingApproval {
                    model.setApproval(id, to: true)
                }
                recordPendingApproval = nil
            }
            Button("Cancel", role: .cancel) { recordPendingApproval = nil }
        } message: {
            Text("Approval enables live MIDI playback. Import validation does not establish that the melody, harmony, or arrangement is correct.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("CAVE CITY BAPTIST CHURCH")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(Color(red: 0.62, green: 0.18, blue: 0.21))
            Text("AI Pianist")
                .font(.largeTitle.bold())
            Text("Traditional hymns • 2008 Baptist Hymnal • MacBook Neo + Korg KRONOS")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var performance: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                GroupBox("Sound and Instrument") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Play through", selection: $model.selectedMIDI) {
                            Text("Mac sampled piano").tag(-1)
                            ForEach(model.midiOutputs) { dest in
                                Text(dest.name).tag(dest.id)
                            }
                        }
                        .disabled(model.isPlaying)

                        HStack {
                            Button("Refresh MIDI Devices") { model.refreshMIDI() }
                                .disabled(model.isPlaying)
                            Button("Load Grand Piano Sound Bank…") { importBank = true }
                                .disabled(model.isPlaying)
                        }
                        Text(model.pianoStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                GroupBox("Performance") {
                    VStack(alignment: .leading, spacing: 13) {
                        Text(model.currentTitle)
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)

                        HStack {
                            Button("Load Original Four-Note Test") { model.useFourNoteTest() }
                                .disabled(model.isPlaying)
                            if !model.isTest {
                                Label(
                                    model.selectedRecord?.approved == true
                                        ? "Manually approved"
                                        : "Approval required",
                                    systemImage: model.selectedRecord?.approved == true ? "checkmark.seal" : "lock"
                                )
                                .foregroundStyle(model.selectedRecord?.approved == true ? Color.green : Color.orange)
                            }
                        }

                        HStack(spacing: 12) {
                            Text("Playback speed")
                            Slider(value: $model.speed, in: 0.5...1.5, step: 0.05)
                                .disabled(model.isPlaying)
                                .accessibilityLabel("Playback speed")
                            Text(String(format: "%.2f×", model.speed))
                                .monospacedDigit()
                                .frame(width: 62)
                        }

                        HStack(spacing: 12) {
                            Button {
                                model.play()
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .frame(minWidth: 90)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canPlay)

                            Button {
                                model.pauseResume()
                            } label: {
                                Label(model.isPaused ? "Resume" : "Pause",
                                      systemImage: model.isPaused ? "play" : "pause")
                            }
                            .disabled(!model.isPlaying)

                            Spacer()

                            Button {
                                model.stop()
                            } label: {
                                Label("EMERGENCY STOP", systemImage: "stop.fill")
                                    .fontWeight(.bold)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .keyboardShortcut(.escape, modifiers: [])
                            .accessibilityHint("Immediately stop local audio and send MIDI sound-off commands")
                        }

                        Text("Imported arrangements cannot play until a person reviews and approves them in the Hymnal Library.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                statusPanel
            }
            .padding(24)
            .frame(maxWidth: 940)
            .frame(maxWidth: .infinity)
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text("The 2008 LifeWay Baptist Hymnal is the numbering reference. No copyrighted sheet music is bundled.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox("Import an authorized MIDI arrangement") {
                HStack(spacing: 12) {
                    TextField("Hymn number", text: $hymnNumber)
                        .frame(width: 128)
                        .accessibilityLabel("Hymn number")
                    TextField("Hymn title", text: $hymnTitle)
                    Button("Import MIDI…") { importMIDI = true }
                        .disabled(
                            model.isPlaying ||
                            hymnNumber.trimmingCharacters(in: .whitespaces).isEmpty ||
                            hymnTitle.trimmingCharacters(in: .whitespaces).isEmpty
                        )
                }
                .padding(7)
            }

            Text("Imported arrangements • \(model.records.count)")
                .font(.headline)

            if model.records.isEmpty {
                ContentUnavailableView(
                    "No hymns imported",
                    systemImage: "music.note.list",
                    description: Text("Import a MIDI file you are permitted to use. Compare it with the printed score before approving.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.records) { record in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("#\(record.number)  \(record.title)")
                                    .font(.headline)
                                Text("\(record.noteCount) note-on events • \(record.approved ? "User-approved" : "Review required")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Select") { model.chooseHymn(record) }
                                .disabled(model.isPlaying)
                            if record.approved {
                                Button("Revoke Approval") {
                                    model.setApproval(record.id, to: false)
                                }
                                .disabled(model.isPlaying)
                            } else {
                                Button("Approve…") {
                                    recordPendingApproval = record.id
                                    showApprovalConfirmation = true
                                }
                                .disabled(model.isPlaying)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.inset)
            }
            statusPanel
        }
        .padding(24)
        .frame(maxWidth: 940)
        .frame(maxWidth: .infinity)
    }

    private var assistant: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                GroupBox("Local Ollama — musical preparation only") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button("Detect Ollama Models") { model.checkOllama() }
                                .disabled(model.isAsking)
                            if model.models.isEmpty {
                                Text("No model selected")
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("Model", selection: $model.selectedModel) {
                                    ForEach(model.models, id: \.self) { name in
                                        Text(name).tag(name)
                                    }
                                }
                            }
                        }

                        Text("Ask about traditional hymn accompaniment, rehearsal planning or notation questions.")
                            .font(.subheadline)
                        TextEditor(text: $model.aiQuestion)
                            .font(.body)
                            .frame(minHeight: 85)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                            .accessibilityLabel("Question for Ollama")

                        Button(model.isAsking ? "Preparing…" : "Ask Local AI") {
                            model.askAI()
                        }
                        .disabled(model.isAsking || model.isPlaying || model.selectedModel.isEmpty)

                        ScrollView {
                            Text(model.aiResponse)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 180, maxHeight: 270)

                        Text("Ollama receives text questions only. There is no API path from this assistant to the live MIDI engine.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }
                statusPanel
            }
            .padding(24)
            .frame(maxWidth: 940)
            .frame(maxWidth: .infinity)
        }
    }

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                GroupBox("First-use checklist") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Connect MacBook USB-C to KRONOS square USB-B with a data cable.", systemImage: "cable.connector")
                        Label("Choose a KRONOS grand piano Program on MIDI channel 1.", systemImage: "pianokeys")
                        Label("Turn the sanctuary soundboard and KRONOS volume down before any test.", systemImage: "speaker.wave.1")
                        Label("Refresh MIDI and select the KRONOS destination.", systemImage: "arrow.clockwise")
                        Label("Play the original four-note test, then test STOP and Pause.", systemImage: "checkmark.circle")
                        Label("Only import and approve authorized, musically reviewed arrangements.", systemImage: "checkmark.seal")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                GroupBox("Important limitations") {
                    Text("""
                    This is an initial native Mac development build. It does not yet read printed hymn pages, automatically follow stanzas, or independently validate the musical notes. Pause releases sustained notes; resume does not reconstruct them. The software STOP button cannot replace the physical instrument/PA mute if the Mac stops responding.
                    """)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                statusPanel
            }
            .padding(24)
            .frame(maxWidth: 940)
            .frame(maxWidth: .infinity)
        }
    }

    private var statusPanel: some View {
        GroupBox("System Status") {
            Text(model.status)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .accessibilityLabel("System status: \(model.status)")
        }
    }
}
