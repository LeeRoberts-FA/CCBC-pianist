import Foundation

// Compiled together with CCBCPianist/Services/MIDIFileDecoder.swift.
// Pure parser smoke tests; no hardware and no copyrighted hymn files.
func be32(_ value: Int) -> [UInt8] {
    [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255),
     UInt8((value >> 8) & 255), UInt8(value & 255)]
}

let track: [UInt8] = [
    0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20, // tempo 120 BPM
    0x00, 0x90, 0x3C, 0x40,             // C4 on
    0x00, 0x40, 0x40,                   // E4 on, running status
    0x83, 0x60, 0x80, 0x3C, 0x00,       // after 480 ticks, C4 off
    0x00, 0x40, 0x00,                   // E4 off, running status
    0x00, 0xFF, 0x2F, 0x00              // end track
]
let bytes: [UInt8] = [
    0x4D, 0x54, 0x68, 0x64,             // MThd
    0, 0, 0, 6,                        // header length
    0, 0,                              // format 0
    0, 1,                              // 1 track
    0x01, 0xE0,                        // PPQ 480
    0x4D, 0x54, 0x72, 0x6B             // MTrk
] + be32(track.count) + track

do {
    let events = try MIDIFileDecoder.parse(Data(bytes))
    precondition(events.count == 4, "Expected 4 note messages")
    precondition(events.filter(\.isNoteOn).count == 2, "Expected two simultaneous notes")
    precondition(events[0].time == 0 && events[1].time == 0, "Notes should start together")
    precondition(abs(events[2].time - 0.5) < 0.000001, "Expected half-second note duration")
    precondition(events[2].status == 0x80 && events[3].status == 0x80, "Expected note offs")

    do {
        _ = try MIDIFileDecoder.parse(Data(bytes.dropLast(1)))
        fatalError("Truncated MIDI must be rejected")
    } catch {
        // Correct: malformed input rejected before performing.
    }

    let test = MIDIFileDecoder.fourNoteTest()
    precondition(test.count == 8 && test.filter(\.isNoteOn).count == 4)
    print("MIDI PARSER SMOKE TEST PASSED")
} catch {
    fatalError("Unexpected parser failure: \(error)")
}
