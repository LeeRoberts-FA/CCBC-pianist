import SwiftUI
import UniformTypeIdentifiers

// MARK: - Visual identity

private enum SanctuaryTheme {
    static let midnight = Color(red: 0.040, green: 0.079, blue: 0.125)
    static let navy = Color(red: 0.063, green: 0.149, blue: 0.220)
    static let slate = Color(red: 0.103, green: 0.190, blue: 0.267)
    static let burgundy = Color(red: 0.620, green: 0.157, blue: 0.177)
    static let ruby = Color(red: 0.78, green: 0.25, blue: 0.28)
    static let gold = Color(red: 0.901, green: 0.787, blue: 0.565)
    static let ivory = Color(red: 0.976, green: 0.959, blue: 0.911)
    static let muted = Color(red: 0.67, green: 0.73, blue: 0.79)
    static let border = Color.white.opacity(0.10)
}

private enum ConsoleSection: String, CaseIterable, Identifiable {
    case pianist = "Pianist"
    case hymnal = "Hymnal Library"
    case assistant = "AI Assistant"
    case setup = "Instrument Setup"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pianist: return "pianokeys"
        case .hymnal: return "books.vertical"
        case .assistant: return "sparkles.rectangle.stack"
        case .setup: return "slider.horizontal.3"
        }
    }

    var subtitle: String {
        switch self {
        case .pianist: return "The performance console"
        case .hymnal: return "Review and prepare your music"
        case .assistant: return "Local hymn preparation"
        case .setup: return "Sound, MIDI, and safety"
        }
    }
}

private struct ConsoleCard<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    init(_ title: String, detail: String = "", @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(SanctuaryTheme.ivory)
                Spacer(minLength: 8)
                if !detail.isEmpty {
                    Text(detail.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(SanctuaryTheme.muted)
                }
            }
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [SanctuaryTheme.slate.opacity(0.94), SanctuaryTheme.navy.opacity(0.94)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(SanctuaryTheme.border, lineWidth: 1)
        )
    }
}

private struct ConsoleAction: View {
    let title: String
    let symbol: String
    var tint: Color = SanctuaryTheme.gold
    var foreground: Color = SanctuaryTheme.midnight
    var emphasized = false
    let action: () -> Void

    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(minHeight: 24)
                .padding(.horizontal, emphasized ? 22 : 16)
                .padding(.vertical, emphasized ? 12 : 9)
                .foregroundStyle(foreground)
                .background(tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
    }
}

private struct StatusTag: View {
    let title: String
    let symbol: String
    var accent = SanctuaryTheme.gold

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(accent.opacity(0.09), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(0.24), lineWidth: 1))
    }
}

// MARK: - Sanctuary console

struct ContentView: View {
    @EnvironmentObject private var model: PianistViewModel

    @State private var selection: ConsoleSection = .pianist
    @State private var importMIDI = false
    @State private var importBank = false
    @State private var hymnNumber = ""
    @State private var hymnTitle = ""
    @State private var recordPendingApproval: UUID?
    @State private var showApprovalConfirmation = false
    @State private var libraryFilter = ""

    private var midiTypes: [UTType] {
        [UTType(filenameExtension: "mid") ?? .data,
         UTType(filenameExtension: "midi") ?? .data]
    }
    private var pianoTypes: [UTType] {
        [UTType(filenameExtension: "sf2") ?? .data,
         UTType(filenameExtension: "dls") ?? .data]
    }
    private var destinationLabel: String {
        if model.selectedMIDI == -1 { return "Mac sampled piano" }
        return model.midiOutputs.first(where: { $0.id == model.selectedMIDI })?.name
            ?? "Disconnected MIDI destination"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 225)

            Rectangle()
                .fill(SanctuaryTheme.border)
                .frame(width: 1)

            VStack(spacing: 0) {
                topBar

                Rectangle()
                    .fill(SanctuaryTheme.border)
                    .frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        pageHeading

                        switch selection {
                        case .pianist:
                            performancePage
                        case .hymnal:
                            hymnalPage
                        case .assistant:
                            assistantPage
                        case .setup:
                            setupPage
                        }

                        statusPanel
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 26)
                    .frame(maxWidth: 1080)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(
                LinearGradient(
                    colors: [SanctuaryTheme.midnight, SanctuaryTheme.navy.opacity(0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .background(SanctuaryTheme.midnight)
        .frame(minWidth: 880, minHeight: 630)
        .preferredColorScheme(.dark)
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
            case .success(let url):
                model.loadPianoBank(url)
            case .failure(let error):
                model.status = "Sound bank selection failed: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "Approve only after reviewing the arrangement against the printed score",
            isPresented: $showApprovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("I reviewed this score — Approve") {
                if let id = recordPendingApproval {
                    model.setApproval(id, to: true)
                }
                recordPendingApproval = nil
            }
            Button("Cancel", role: .cancel) {
                recordPendingApproval = nil
            }
        } message: {
            Text("This approval lets the imported file play. It does not independently prove the melody, harmony, or timing is correct.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(SanctuaryTheme.gold.opacity(0.10))
                        .frame(width: 47, height: 47)
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(SanctuaryTheme.gold.opacity(0.55), lineWidth: 1)
                        .frame(width: 47, height: 47)
                    Image(systemName: "pianokeys")
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(SanctuaryTheme.gold)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("CCBC")
                        .font(.system(size: 23, weight: .semibold, design: .serif))
                        .tracking(1.5)
                        .foregroundStyle(SanctuaryTheme.ivory)
                    Text("AI PIANIST")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(2.0)
                        .foregroundStyle(SanctuaryTheme.gold)
                }
            }
            .padding(.bottom, 39)

            Text("THE WORKSPACE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(SanctuaryTheme.muted)
                .padding(.horizontal, 12)
                .padding(.bottom, 14)

            ForEach(ConsoleSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 20)
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Spacer(minLength: 0)
                        if section == selection {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .foregroundStyle(section == selection ? SanctuaryTheme.ivory : SanctuaryTheme.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .fill(section == selection ? SanctuaryTheme.gold.opacity(0.12) : Color.clear)
                    )
                    .overlay(alignment: .leading) {
                        if section == selection {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(SanctuaryTheme.gold)
                                .frame(width: 3, height: 26)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == selection ? [.isSelected] : [])
                .padding(.bottom, 7)
            }

            Spacer(minLength: 30)

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(model.selectedMIDI == -1 ? SanctuaryTheme.muted : SanctuaryTheme.gold)
                        .frame(width: 7, height: 7)
                    Text("OUTPUT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(SanctuaryTheme.muted)
                }
                Text(destinationLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SanctuaryTheme.ivory)
                    .lineLimit(2)
                Text("Church performance system")
                    .font(.system(size: 11))
                    .foregroundStyle(SanctuaryTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(SanctuaryTheme.slate.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 7) {
                Image(systemName: "cross")
                    .font(.system(size: 12))
                Text("FAITH  ·  WORSHIP  ·  MUSIC")
                    .tracking(1)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(SanctuaryTheme.gold.opacity(0.88))
            .padding(.top, 24)
        }
        .padding(.horizontal, 18)
        .padding(.top, 30)
        .padding(.bottom, 26)
        .frame(maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [SanctuaryTheme.navy, SanctuaryTheme.midnight],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("SANCTUARY CONSOLE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2.1)
                .foregroundStyle(SanctuaryTheme.muted)

            Spacer()

            StatusTag(
                title: "DEVELOPMENT BUILD",
                symbol: "hammer",
                accent: SanctuaryTheme.gold
            )
            StatusTag(
                title: model.isPlaying ? (model.isPaused ? "PAUSED" : "PLAYING") : "STANDBY",
                symbol: model.isPlaying ? "waveform" : "circle.dotted",
                accent: model.isPlaying ? .green : SanctuaryTheme.muted
            )
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 17)
    }

    private var pageHeading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(selection.rawValue)
                .font(.system(size: 34, weight: .regular, design: .serif))
                .foregroundStyle(SanctuaryTheme.ivory)

            Text(selection.subtitle)
                .font(.system(size: 14))
                .foregroundStyle(SanctuaryTheme.muted)
        }
    }

    private var performancePage: some View {
        VStack(alignment: .leading, spacing: 17) {
            performanceHero

            ConsoleCard("Performance controls", detail: "Manual operation") {
                HStack(spacing: 12) {
                    ConsoleAction(
                        title: "Play arrangement",
                        symbol: "play.fill",
                        tint: SanctuaryTheme.gold,
                        foreground: SanctuaryTheme.midnight,
                        emphasized: true
                    ) { model.play() }
                    .disabled(!model.canPlay)

                    ConsoleAction(
                        title: model.isPaused ? "Resume" : "Pause",
                        symbol: model.isPaused ? "play" : "pause.fill",
                        tint: SanctuaryTheme.slate,
                        foreground: SanctuaryTheme.ivory
                    ) { model.pauseResume() }
                    .disabled(!model.isPlaying)

                    Spacer(minLength: 5)

                    ConsoleAction(
                        title: "STOP ALL NOTES",
                        symbol: "stop.fill",
                        tint: SanctuaryTheme.burgundy,
                        foreground: .white,
                        emphasized: true
                    ) { model.stop() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityHint("Silences sampler and sends MIDI sustain-off, all-notes-off and all-sound-off")
                }

                Rectangle()
                    .fill(SanctuaryTheme.border)
                    .frame(height: 1)

                HStack(spacing: 18) {
                    Text("Tempo")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SanctuaryTheme.ivory)

                    Slider(value: $model.speed, in: 0.5...1.5, step: 0.05)
                        .tint(SanctuaryTheme.gold)
                        .disabled(model.isPlaying)
                        .accessibilityLabel("Playback speed")

                    Text(String(format: "%.2f×", model.speed))
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SanctuaryTheme.gold)
                        .frame(width: 66)
                }
            }

            ConsoleCard("Instrument routing", detail: "Sound source") {
                HStack(spacing: 14) {
                    Picker("Destination", selection: $model.selectedMIDI) {
                        Text("Mac sampled piano").tag(-1)
                        ForEach(model.midiOutputs) { output in
                            Text(output.name).tag(output.id)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(model.isPlaying)

                    ConsoleAction(
                        title: "Refresh",
                        symbol: "arrow.clockwise",
                        tint: SanctuaryTheme.slate,
                        foreground: SanctuaryTheme.ivory
                    ) { model.refreshMIDI() }
                    .disabled(model.isPlaying)
                }

                Text(model.pianoStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(SanctuaryTheme.muted)
            }
        }
    }

    private var performanceHero: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.25, blue: 0.31),
                            SanctuaryTheme.navy,
                            SanctuaryTheme.midnight
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(SanctuaryTheme.gold.opacity(0.13), lineWidth: 1)
                .frame(width: 280, height: 280)
                .offset(x: 540, y: -42)
            Circle()
                .strokeBorder(SanctuaryTheme.gold.opacity(0.10), lineWidth: 1)
                .frame(width: 210, height: 210)
                .offset(x: 575, y: -6)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 18) {
                    StatusTag(
                        title: model.isTest
                            ? "ORIGINAL TEST MUSIC"
                            : (model.selectedRecord?.approved == true ? "USER APPROVED" : "REVIEW REQUIRED"),
                        symbol: model.isTest ? "music.note" : "checkmark.seal",
                        accent: SanctuaryTheme.gold
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("CURRENT SELECTION")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(SanctuaryTheme.muted)

                        Text(model.currentTitle)
                            .font(.system(size: 33, weight: .regular, design: .serif))
                            .foregroundStyle(SanctuaryTheme.ivory)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .accessibilityAddTraits(.isHeader)

                        Text("Faithful accompaniment starts with verified music.")
                            .font(.system(size: 13))
                            .foregroundStyle(SanctuaryTheme.muted)
                    }

                    ConsoleAction(
                        title: "Select four-note test",
                        symbol: "music.note.list",
                        tint: SanctuaryTheme.gold.opacity(0.11),
                        foreground: SanctuaryTheme.gold
                    ) { model.useFourNoteTest() }
                    .disabled(model.isPlaying)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "pianokeys")
                    .font(.system(size: 112, weight: .ultraLight))
                    .foregroundStyle(SanctuaryTheme.gold.opacity(0.72))
                    .frame(width: 188)
                    .accessibilityHidden(true)
            }
            .padding(27)
        }
        .frame(minHeight: 226)
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(SanctuaryTheme.gold.opacity(0.24), lineWidth: 1)
        )
    }

    private var hymnalPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            ConsoleCard("Import an arrangement", detail: "2008 Baptist Hymnal") {
                Text("Build a library of scores your church is authorized to use. Imported MIDI is locked until reviewed against the printed arrangement.")
                    .font(.system(size: 13))
                    .foregroundStyle(SanctuaryTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    TextField("Hymn no.", text: $hymnNumber)
                        .frame(width: 100)
                        .accessibilityLabel("Hymn number")

                    TextField("Hymn title", text: $hymnTitle)

                    ConsoleAction(
                        title: "Import MIDI",
                        symbol: "square.and.arrow.down",
                        tint: SanctuaryTheme.gold
                    ) { importMIDI = true }
                    .disabled(
                        model.isPlaying ||
                        hymnNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        hymnTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
                .textFieldStyle(.roundedBorder)
            }

            ConsoleCard("Arrangement library", detail: "\(model.records.count) imported") {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(SanctuaryTheme.muted)
                    TextField("Search hymns by number or title", text: $libraryFilter)
                        .textFieldStyle(.plain)
                        .foregroundStyle(SanctuaryTheme.ivory)
                }
                .padding(12)
                .background(SanctuaryTheme.midnight.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SanctuaryTheme.border))

                let visible = model.records.filter {
                    libraryFilter.isEmpty ||
                    $0.title.localizedCaseInsensitiveContains(libraryFilter) ||
                    $0.number.localizedCaseInsensitiveContains(libraryFilter)
                }

                if visible.isEmpty {
                    VStack(spacing: 13) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 39, weight: .ultraLight))
                            .foregroundStyle(SanctuaryTheme.gold)
                        Text(model.records.isEmpty ? "Your hymnal library starts here" : "No matching hymns")
                            .font(.system(size: 21, weight: .regular, design: .serif))
                            .foregroundStyle(SanctuaryTheme.ivory)
                        Text(model.records.isEmpty
                             ? "Import your first authorized arrangement and review it before performing."
                             : "Try another hymn title or number.")
                            .font(.system(size: 12))
                            .foregroundStyle(SanctuaryTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    ForEach(visible) { record in
                        HStack(spacing: 14) {
                            Text("#\(record.number)")
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundStyle(SanctuaryTheme.gold)
                                .frame(width: 70, alignment: .leading)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(record.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(SanctuaryTheme.ivory)
                                Text("\(record.noteCount) note events")
                                    .font(.system(size: 11))
                                    .foregroundStyle(SanctuaryTheme.muted)
                            }

                            Spacer(minLength: 8)

                            StatusTag(
                                title: record.approved ? "USER APPROVED" : "REVIEW REQUIRED",
                                symbol: record.approved ? "checkmark.circle" : "lock",
                                accent: record.approved ? .green : SanctuaryTheme.gold
                            )

                            ConsoleAction(
                                title: "Select",
                                symbol: "checkmark",
                                tint: SanctuaryTheme.slate,
                                foreground: SanctuaryTheme.ivory
                            ) {
                                model.chooseHymn(record)
                                selection = .pianist
                            }
                            .disabled(model.isPlaying)

                            if record.approved {
                                ConsoleAction(
                                    title: "Revoke",
                                    symbol: "lock",
                                    tint: SanctuaryTheme.burgundy.opacity(0.65),
                                    foreground: SanctuaryTheme.ivory
                                ) { model.setApproval(record.id, to: false) }
                                .disabled(model.isPlaying)
                            } else {
                                ConsoleAction(
                                    title: "Approve…",
                                    symbol: "checkmark.seal",
                                    tint: SanctuaryTheme.gold
                                ) {
                                    recordPendingApproval = record.id
                                    showApprovalConfirmation = true
                                }
                                .disabled(model.isPlaying)
                            }
                        }
                        .padding(.vertical, 8)

                        if record.id != visible.last?.id {
                            Rectangle().fill(SanctuaryTheme.border).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private var assistantPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            ConsoleCard("Your local music assistant", detail: "Powered by Ollama") {
                Text("Prepare rehearsals, discuss hymn structure and organize ideas. Your AI assistant never sends notes to the live instrument.")
                    .font(.system(size: 13))
                    .foregroundStyle(SanctuaryTheme.muted)

                HStack {
                    ConsoleAction(
                        title: "Detect local models",
                        symbol: "arrow.clockwise",
                        tint: SanctuaryTheme.slate,
                        foreground: SanctuaryTheme.ivory
                    ) { model.checkOllama() }
                    .disabled(model.isAsking)

                    Spacer(minLength: 14)

                    if model.models.isEmpty {
                        StatusTag(title: "NO MODEL SELECTED", symbol: "circle.dotted", accent: SanctuaryTheme.muted)
                    } else {
                        Picker("Model", selection: $model.selectedModel) {
                            ForEach(model.models, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .frame(maxWidth: 340)
                    }
                }
            }

            ConsoleCard("Ask a question", detail: "Preparation only") {
                TextEditor(text: $model.aiQuestion)
                    .font(.system(size: 14))
                    .foregroundStyle(SanctuaryTheme.ivory)
                    .scrollContentBackground(.hidden)
                    .frame(height: 108)
                    .padding(10)
                    .background(SanctuaryTheme.midnight.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SanctuaryTheme.border))
                    .accessibilityLabel("Question for local Ollama assistant")

                HStack {
                    Spacer()
                    ConsoleAction(
                        title: model.isAsking ? "Preparing…" : "Ask assistant",
                        symbol: "sparkles",
                        tint: SanctuaryTheme.gold,
                        emphasized: true
                    ) { model.askAI() }
                    .disabled(model.isAsking || model.isPlaying || model.selectedModel.isEmpty)
                }

                Text("RESPONSE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.7)
                    .foregroundStyle(SanctuaryTheme.muted)

                Text(model.aiResponse)
                    .font(.system(size: 13))
                    .foregroundStyle(SanctuaryTheme.ivory)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(SanctuaryTheme.midnight.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var setupPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            ConsoleCard("Keyboard connection", detail: "MacBook Neo → Korg KRONOS") {
                setupItem("1", "Connect the USB-B port", "Use a USB-C to USB-B data cable from the Mac to the KRONOS square USB-B connector.")
                setupItem("2", "Select acoustic grand piano", "Choose your KRONOS piano Program and confirm it receives notes on MIDI channel 1.")
                setupItem("3", "Start at low volume", "Lower the KRONOS and sanctuary soundboard before sending the first test notes.")
                setupItem("4", "Verify real MIDI output", "Refresh destinations, select the KRONOS, play four notes, and verify the physical STOP/mute route.")
            }

            ConsoleCard("Audio and diagnostics", detail: "Sound source") {
                Text(model.pianoStatus)
                    .font(.system(size: 13))
                    .foregroundStyle(SanctuaryTheme.muted)
                HStack(spacing: 12) {
                    ConsoleAction(
                        title: "Load piano sample bank",
                        symbol: "square.and.arrow.down",
                        tint: SanctuaryTheme.gold
                    ) { importBank = true }
                    .disabled(model.isPlaying)

                    ConsoleAction(
                        title: "Refresh MIDI",
                        symbol: "arrow.clockwise",
                        tint: SanctuaryTheme.slate,
                        foreground: SanctuaryTheme.ivory
                    ) { model.refreshMIDI() }
                    .disabled(model.isPlaying)
                }
            }

            ConsoleCard("Before Sunday worship", detail: "Performance standard") {
                Text("This build must be rehearsed and validated before congregational use. Imported arrangements need musician approval; printed sheet recognition, stanza handling, and automatic introductions are not yet available.")
                    .font(.system(size: 13))
                    .foregroundStyle(SanctuaryTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("If the Mac or application becomes unresponsive, mute the instrument or sanctuary soundboard. Software STOP is not a substitute for hardware mute.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SanctuaryTheme.ivory)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setupItem(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(SanctuaryTheme.gold)
                .frame(width: 27, height: 27)
                .background(SanctuaryTheme.gold.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SanctuaryTheme.ivory)

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(SanctuaryTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    private var statusPanel: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: "waveform.path")
                .foregroundStyle(SanctuaryTheme.gold)
                .font(.system(size: 17))
            VStack(alignment: .leading, spacing: 3) {
                Text("SYSTEM STATUS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(SanctuaryTheme.muted)

                Text(model.status)
                    .font(.system(size: 12))
                    .foregroundStyle(SanctuaryTheme.ivory)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(16)
        .background(SanctuaryTheme.gold.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(SanctuaryTheme.gold.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(PianistViewModel())
    }
}
#endif
