import Foundation
import CoreMIDI

struct MIDIDestination: Identifiable, Hashable {
    let id: Int
    let name: String
    let endpoint: MIDIEndpointRef

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

final class KronosMIDI {
    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()

    init() {
        let result = MIDIClientCreate("CCBC AI Pianist" as CFString, nil, nil, &client)
        if result == noErr {
            let status = MIDIOutputPortCreate(client, "CCBC Piano Output" as CFString, &outputPort)
            if status != noErr { outputPort = 0 }
        }
    }

    deinit {
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    func destinations() -> [MIDIDestination] {
        (0..<Int(MIDIGetNumberOfDestinations())).map { i in
            let endpoint = MIDIGetDestination(i)
            var property: Unmanaged<CFString>?
            let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &property)
            let name: String
            if status == noErr, let value = property {
                name = value.takeRetainedValue() as String
            } else {
                name = "MIDI Destination \(i)"
            }
            return MIDIDestination(id: Int(endpoint), name: name, endpoint: endpoint)
        }
    }

    @discardableResult
    func send(_ event: MIDIEvent, to endpoint: MIDIEndpointRef) -> Bool {
        guard outputPort != 0, endpoint != 0 else { return false }
        // Only our controlled three-byte piano messages ever leave the application.
        let bytes = [event.status, event.data1, event.data2]
        var packets = MIDIPacketList()
        let first = MIDIPacketListInit(&packets)
        bytes.withUnsafeBufferPointer { buffer in
            _ = MIDIPacketListAdd(
                &packets,
                MemoryLayout<MIDIPacketList>.size,
                first,
                0,
                buffer.count,
                buffer.baseAddress!
            )
        }
        return MIDISend(outputPort, endpoint, &packets) == noErr
    }

    func silence(_ endpoint: MIDIEndpointRef) {
        for channel in 0..<16 {
            for cc in [UInt8(64), UInt8(123), UInt8(120)] {
                _ = send(
                    MIDIEvent(time: 0, status: 0xB0 | UInt8(channel), data1: cc, data2: 0),
                    to: endpoint
                )
            }
        }
    }
}
