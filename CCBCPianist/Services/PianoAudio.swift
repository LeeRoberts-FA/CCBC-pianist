import Foundation
import AVFoundation

/// Local sampled-instrument output. No oscillator or synthetic bell fallback is used.
final class PianoAudio {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()

    private(set) var isReady = false
    private(set) var description = "Looking for a compatible sampled piano…"

    init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)

        do {
            try engine.start()
        } catch {
            description = "Mac audio engine: \(error.localizedDescription)"
        }

        let paths = [
            "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls",
            "/Library/Audio/Sounds/Banks/gs_instruments.dls"
        ]
        if let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            loadBank(URL(fileURLWithPath: path))
        } else {
            description = "No system piano bank was found. Choose a licensed .sf2 or .dls sound bank."
        }
    }

    func loadBank(_ url: URL) {
        silence()
        isReady = false
        do {
            // General MIDI Acoustic Grand Piano, program 0, melodic bank 121.
            try sampler.loadSoundBankInstrument(at: url, program: 0, bankMSB: 0x79, bankLSB: 0)
            if !engine.isRunning { try engine.start() }
            isReady = true
            description = "Sampled piano ready: \(url.lastPathComponent)"
        } catch {
            description = "Cannot load piano bank: \(error.localizedDescription)"
        }
    }

    func send(_ event: MIDIEvent) {
        guard isReady else { return }
        switch event.status {
        case 0x90:
            sampler.startNote(event.data1, withVelocity: event.data2, onChannel: 0)
        case 0x80:
            sampler.stopNote(event.data1, onChannel: 0)
        case 0xB0:
            sampler.sendController(event.data1, withValue: event.data2, onChannel: 0)
        default:
            break
        }
    }

    func silence() {
        sampler.sendController(64, withValue: 0, onChannel: 0)
        sampler.sendController(123, withValue: 0, onChannel: 0)
        sampler.sendController(120, withValue: 0, onChannel: 0)
    }
}
