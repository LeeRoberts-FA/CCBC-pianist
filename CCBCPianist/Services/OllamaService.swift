import Foundation

struct OllamaModelList: Decodable {
    struct Model: Decodable {
        let name: String
    }
    let models: [Model]
}

private struct OllamaStreamChunk: Decodable {
    let response: String?
    let done: Bool?
    let error: String?
}

enum OllamaError: LocalizedError {
    case invalidEndpoint
    case insecureEndpoint
    case server(Int)
    case remote(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Enter a complete Ollama address, such as http://192.168.1.20:11434."
        case .insecureEndpoint:
            return "Unencrypted HTTP is allowed only for local, private-LAN or Tailscale addresses. Use HTTPS for other servers."
        case .server(let code):
            return "The Ollama server returned HTTP \(code). Verify the address and server status."
        case .remote(let details):
            return "Ollama reported an error: \(details)"
        case .emptyResponse:
            return "The model completed without any answer. Check the selected model and server logs."
        }
    }
}

struct OllamaService {
    static let defaultEndpoint = "http://127.0.0.1:11434"

    // Ollama on a private LAN/VPN may use HTTP. Never invite users to expose it on the internet.
    private func checkedBase(_ rawValue: String) throws -> URL {
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: raw),
              let scheme = parts.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let hostname = parts.host?.lowercased(),
              !hostname.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else {
            throw OllamaError.invalidEndpoint
        }

        if scheme == "http" && !isPrivateHost(hostname) {
            throw OllamaError.insecureEndpoint
        }
        guard let url = parts.url else { throw OllamaError.invalidEndpoint }
        return url
    }

    private func isPrivateHost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "::1"
            || host.hasSuffix(".local") || host.hasSuffix(".ts.net")
            || host.hasSuffix(".tailscale.net") || !host.contains(".") {
            return true
        }

        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }

        let a = Int(parts[0]), b = Int(parts[1])
        return a == 10
            || (a == 172 && (16...31).contains(b))
            || (a == 192 && b == 168)
            || (a == 100 && (64...127).contains(b))
            || (a == 127)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    func models(endpoint: String) async throws -> [String] {
        let base = try checkedBase(endpoint)
        let session = makeSession()
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: base.appendingPathComponent("api/tags"))
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OllamaError.server(status) }
        return try JSONDecoder().decode(OllamaModelList.self, from: data).models.map(\.name)
    }

    // Stream short pieces as soon as the server produces them. AI never calls the MIDI engine.
    func askStreaming(
        endpoint: String,
        model: String,
        question: String,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws {
        let base = try checkedBase(endpoint)
        let session = makeSession()
        defer { session.finishTasksAndInvalidate() }

        let system = """
        You are a preparation-only assistant for Cave City Baptist Church's AI Pianist.
        The church references the 2008 LifeWay Baptist Hymnal.
        Do not claim to have inspected a hymn score unless it was supplied.
        Do not invent hymn numbers, musical notes, permissions, or verified arrangements.
        Provide practical, concise, traditional Baptist music-rehearsal advice.
        You have no access to the audio or MIDI engine, cannot approve imports,
        and cannot initiate playback.
        """

        var request = URLRequest(url: base.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "system": system,
            "prompt": question,
            "stream": true,
            "keep_alive": "3m",
            "options": ["num_ctx": 2048, "num_predict": 320]
        ])

        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OllamaError.server(status) }

        var receivedText = false

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8) else { continue }

            let part = try JSONDecoder().decode(OllamaStreamChunk.self, from: data)
            if let issue = part.error, !issue.isEmpty {
                throw OllamaError.remote(issue)
            }
            if let token = part.response, !token.isEmpty {
                receivedText = true
                await onToken(token)
            }
            if part.done == true { break }
        }

        try Task.checkCancellation()
        guard receivedText else { throw OllamaError.emptyResponse }
    }
}
