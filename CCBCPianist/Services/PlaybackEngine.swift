import Foundation
import CoreMIDI

/// Deterministic, non-AI playback. All MIDI output is serialized with the stop lock.
/// Pausing releases sounding notes; resuming does not recreate a held chord.
final class PlaybackEngine {
    private let lock = NSLock()
    private let sound: PianoAudio
    private let midi: KronosMIDI

    private var runID = 0
    private var active = false
    private var paused = false
    private var startUptime = 0.0
    private var pauseUptime = 0.0
    private var pausedDuration = 0.0
    private var currentDestination: MIDIEndpointRef?

    init(sound: PianoAudio, midi: KronosMIDI) {
        self.sound = sound
        self.midi = midi
    }

    var isPlaying: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func start(
        events: [MIDIEvent],
        speed: Double,
        destination: MIDIEndpointRef?,
        onFinished: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        lock.lock()
        guard !active, !events.isEmpty else { lock.unlock(); return }
        runID += 1
        let generation = runID
        active = true
        paused = false
        startUptime = ProcessInfo.processInfo.systemUptime
        pauseUptime = 0
        pausedDuration = 0
        currentDestination = destination
        lock.unlock()

        let factor = max(0.5, min(1.5, speed))
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            for event in events {
                while true {
                    self.lock.lock()
                    guard self.active, self.runID == generation else {
                        self.lock.unlock()
                        return
                    }
                    if self.paused {
                        self.lock.unlock()
                        Thread.sleep(forTimeInterval: 0.005)
                        continue
                    }
                    let now = ProcessInfo.processInfo.systemUptime
                    let played = (now - self.startUptime - self.pausedDuration) * factor
                    if played >= event.time {
                        if let endpoint = destination {
                            let success = self.midi.send(event, to: endpoint)
                            if !success {
                                self.active = false
                                self.runID += 1
                                self.midi.silence(endpoint)
                                self.lock.unlock()
                                DispatchQueue.main.async { onError("MIDI output failed. Check the KRONOS connection.") }
                                return
                            }
                        } else {
                            self.sound.send(event)
                        }
                        self.lock.unlock()
                        break
                    }
                    self.lock.unlock()
                    Thread.sleep(forTimeInterval: min(0.005, max(0.001, (event.time - played) / factor)))
                }
            }

            self.lock.lock()
            let completed = self.active && self.runID == generation
            if completed {
                self.active = false
                self.silenceLocked()
            }
            self.lock.unlock()
            if completed { DispatchQueue.main.async { onFinished() } }
        }
    }

    func pause() {
        lock.lock()
        defer { lock.unlock() }
        guard active, !paused else { return }
        paused = true
        pauseUptime = ProcessInfo.processInfo.systemUptime
        silenceLocked()
    }

    func resume() {
        lock.lock()
        defer { lock.unlock() }
        guard active, paused else { return }
        pausedDuration += ProcessInfo.processInfo.systemUptime - pauseUptime
        paused = false
    }

    func stop() {
        lock.lock()
        runID += 1
        active = false
        paused = false
        silenceLocked()
        lock.unlock()
    }

    private func silenceLocked() {
        sound.silence()
        if let endpoint = currentDestination { midi.silence(endpoint) }
    }
}
