import Foundation

struct MIDIEvent: Equatable {
    let time: TimeInterval
    let status: UInt8
    let data1: UInt8
    let data2: UInt8

    var isNoteOn: Bool { status == 0x90 && data2 > 0 }
}

enum MIDIFileError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        if case .invalid(let message) = self { return message }
        return "Unable to read MIDI file."
    }
}

struct MIDIFileDecoder {
    private struct Reader {
        var data: [UInt8]
        var offset = 0
        var remaining: Int { data.count - offset }

        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, count <= remaining else {
                throw MIDIFileError.invalid("Unexpected end of MIDI file.")
            }
            defer { offset += count }
            return Array(data[offset..<(offset + count)])
        }

        mutating func byte() throws -> UInt8 { try take(1)[0] }

        mutating func integer(_ count: Int) throws -> Int {
            try take(count).reduce(0) { ($0 << 8) | Int($1) }
        }

        mutating func variable() throws -> Int {
            var result = 0
            for _ in 0..<4 {
                let b = try byte()
                result = (result << 7) | Int(b & 0x7f)
                if b & 0x80 == 0 { return result }
            }
            throw MIDIFileError.invalid("Invalid variable-length MIDI value.")
        }

        mutating func signature() throws -> String {
            String(bytes: try take(4), encoding: .ascii) ?? ""
        }
    }

    private struct Raw {
        let tick: Int
        let order: Int
        let status: UInt8
        let d1: UInt8
        let d2: UInt8
    }

    private struct Tempo {
        let tick: Int
        let order: Int
        let microseconds: Int
    }

    static func parse(_ data: Data) throws -> [MIDIEvent] {
        guard data.count <= 12_000_000 else {
            throw MIDIFileError.invalid("MIDI file exceeds the 12 MB import limit.")
        }
        var reader = Reader(data: Array(data))
        guard try reader.signature() == "MThd" else {
            throw MIDIFileError.invalid("This is not a Standard MIDI File.")
        }
        let headerLength = try reader.integer(4)
        guard (6...256).contains(headerLength) else {
            throw MIDIFileError.invalid("Invalid MIDI header.")
        }
        let format = try reader.integer(2)
        let tracks = try reader.integer(2)
        let division = try reader.integer(2)
        guard (format == 0 || format == 1), (1...128).contains(tracks) else {
            throw MIDIFileError.invalid("Only MIDI formats 0 and 1 are supported.")
        }
        guard division > 0, division & 0x8000 == 0 else {
            throw MIDIFileError.invalid("SMPTE timing is not supported; export using ticks per quarter note.")
        }
        _ = try reader.take(headerLength - 6)

        var raw: [Raw] = []
        var tempos: [Tempo] = [Tempo(tick: 0, order: -1, microseconds: 500_000)]
        var order = 0

        for _ in 0..<tracks {
            guard try reader.signature() == "MTrk" else {
                throw MIDIFileError.invalid("A MIDI track header is missing.")
            }
            let length = try reader.integer(4)
            guard length <= reader.remaining else {
                throw MIDIFileError.invalid("Truncated MIDI track.")
            }
            var track = Reader(data: try reader.take(length))
            var tick = 0
            var running: UInt8 = 0

            while track.remaining > 0 {
                let delta = try track.variable()
                guard tick <= Int.max - delta else {
                    throw MIDIFileError.invalid("Invalid MIDI track timing.")
                }
                tick += delta
                let first = try track.byte()
                var status = first
                if first < 0x80 {
                    guard running >= 0x80, running < 0xF0 else {
                        throw MIDIFileError.invalid("Invalid MIDI running status.")
                    }
                    track.offset -= 1
                    status = running
                } else if first < 0xF0 {
                    running = first
                } else {
                    running = 0
                }

                if status == 0xFF {
                    let meta = try track.byte()
                    let size = try track.variable()
                    let contents = try track.take(size)
                    if meta == 0x51 && size == 3 {
                        let micros = (Int(contents[0]) << 16)
                            | (Int(contents[1]) << 8) | Int(contents[2])
                        if micros > 0 {
                            tempos.append(Tempo(tick: tick, order: order, microseconds: micros))
                            order += 1
                        }
                    }
                    if meta == 0x2F { break }
                } else if status == 0xF0 || status == 0xF7 {
                    let length = try track.variable()
                    _ = try track.take(length) // SysEx ignored for instrument safety
                } else if status < 0xF0 {
                    let kind = status & 0xF0
                    let d1 = try track.byte()
                    let d2: UInt8 = (kind == 0xC0 || kind == 0xD0) ? 0 : try track.byte()
                    guard d1 <= 127, d2 <= 127 else {
                        throw MIDIFileError.invalid("MIDI data byte out of range.")
                    }

                    // Collapse source channels into one church piano voice on MIDI channel 1.
                    if kind == 0x80 || kind == 0x90 || (kind == 0xB0 && d1 == 64) {
                        let normalized: UInt8 = (kind == 0x90 && d2 == 0) ? 0x80 : kind
                        raw.append(Raw(tick: tick, order: order, status: normalized, d1: d1, d2: d2))
                        guard raw.count <= 200_000 else {
                            throw MIDIFileError.invalid("Too many playable MIDI events.")
                        }
                    }
                    order += 1
                } else {
                    throw MIDIFileError.invalid("Unsupported system event in MIDI track.")
                }
            }
        }
        guard raw.contains(where: { $0.status == 0x90 && $0.d2 > 0 }) else {
            throw MIDIFileError.invalid("No playable piano notes were found.")
        }
        raw.sort {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            // At exactly the same tick, release before re-articulation.
            if $0.status == 0x80 && $1.status == 0x90 { return true }
            if $0.status == 0x90 && $1.status == 0x80 { return false }
            return $0.order < $1.order
        }
        tempos.sort {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            return $0.order < $1.order
        }

        var index = 0
        var currentTick = 0
        var currentTempo = 500_000
        var seconds = 0.0
        var output: [MIDIEvent] = []

        for event in raw {
            while index < tempos.count && tempos[index].tick <= event.tick {
                let change = tempos[index]
                seconds += Double(change.tick - currentTick) * Double(currentTempo)
                    / 1_000_000 / Double(division)
                currentTick = change.tick
                currentTempo = change.microseconds
                index += 1
            }
            seconds += Double(event.tick - currentTick) * Double(currentTempo)
                / 1_000_000 / Double(division)
            currentTick = event.tick
            guard seconds.isFinite && seconds < 86_400 else {
                throw MIDIFileError.invalid("MIDI duration exceeds 24 hours.")
            }
            output.append(MIDIEvent(time: seconds, status: event.status, data1: event.d1, data2: event.d2))
        }
        return output
    }

    static func fourNoteTest() -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        for (index, pitch) in [60, 64, 67, 72].enumerated() {
            let time = Double(index) * 0.50
            events.append(MIDIEvent(time: time, status: 0x90, data1: UInt8(pitch), data2: 48))
            events.append(MIDIEvent(time: time + 0.40, status: 0x80, data1: UInt8(pitch), data2: 0))
        }
        return events.sorted { $0.time < $1.time }
    }
}
