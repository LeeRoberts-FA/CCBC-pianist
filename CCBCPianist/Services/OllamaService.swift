import Foundation
import Security

struct OllamaModelList: Decodable {
    struct Model: Decodable { let name: String }
    let models: [Model]
}

private struct OllamaStreamChunk: Decodable {
    let response: String?
    let done: Bool?
    let error: String?
}

enum OllamaConnectionError: LocalizedError {
    case invalidAddress
    case insecureAddress
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Use an Ollama server URL such as http://127.0.0.1:11434 or https://your-secure-server.example."
        case .insecureAddress:
            return "Remote inference requires HTTPS, or an SSH tunnel through 127.0.0.1. Do not expose Ollama's raw HTTP port on the public internet."
        case .keychain(let status):
            return "macOS Keychain could not save the server token (status \(status))."
        }
    }
}

enum OllamaConnection {
    static let defaultEndpoint = "http://127.0.0.1:11434"
    private static let preference = "CCBC.Ollama.Endpoint"
    private static let keychainService = "org.cavecitybaptist.ccbcaipianist.ollama"

    static func savedEndpoint() -> String {
        UserDefaults.standard.string(forKey: preference) ?? defaultEndpoint
    }

    static func checkedURL(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: trimmed),
              let scheme = parts.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = parts.host?.lowercased(),
              !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else {
            throw OllamaConnectionError.invalidAddress
        }
        // Use local loopback for a directly installed Ollama or for a secure SSH port-forward.
        if scheme == "http" && host != "localhost" && host != "127.0.0.1" && host != "::1" {
            throw OllamaConnectionError.insecureAddress
        }
        guard let url = parts.url else { throw OllamaConnectionError.invalidAddress }
        return url
    }

    private static func keychainQuery(for endpoint: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: endpoint
        ]
    }

    static func loadToken(for endpoint: String) -> String {
        var query = keychainQuery(for: endpoint)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(endpoint: String, token: String) throws {
        let url = try checkedURL(endpoint)
        let canonical = url.absoluteString.hasSuffix("/") ? String(url.absoluteString.dropLast()) : url.absoluteString
        var query = keychainQuery(for: canonical)
        // Delete previous value so repeated saves do not create duplicate Keychain items.
        let deleted = SecItemDelete(query as CFDictionary)
        if deleted != errSecSuccess && deleted != errSecItemNotFound {
            throw OllamaConnectionError.keychain(deleted)
        }
        if !token.isEmpty {
            query[kSecValueData as String] = Data(token.utf8)
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw OllamaConnectionError.keychain(added) }
        }
        UserDefaults.standard.set(canonical, forKey: preference)
    }
}

enum OllamaRequestError: LocalizedError {
    case http(Int)
    case remote(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .http(let code):
            return "Ollama returned HTTP \(code). Check the server URL, token and installed model."
        case .remote(let reason):
            return "Ollama reported: \(reason)"
        case .empty:
            return "The model did not return text. Check its server logs or select another model."
        }
    }
}

struct OllamaService {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    private func request(
        endpoint: String,
        token: String,
        path: String,
        method: String = "GET"
    ) throws -> URLRequest {
        let base = try OllamaConnection.checkedURL(endpoint)
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = method == "GET" ? 15 : 180
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func models(endpoint: String, token: String) async throws -> [String] {
        let session = session()
        defer { session.invalidateAndCancel() }
        let req = try request(endpoint: endpoint, token: token, path: "api/tags")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw OllamaRequestError.http(0)
        }
        guard http.statusCode == 200 else {
            throw OllamaRequestError.http(http.statusCode)
        }
        return try JSONDecoder().decode(OllamaModelList.self, from: data).models.map(\.name)
    }

    /// AI can only return prose. It has no dependency on CoreMIDI, piano audio, or playback.
    func ask(
        endpoint: String,
        token: String,
        model: String,
        question: String,
        onUpdate: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let session = session()
        defer { session.invalidateAndCancel() }

        let system = """
        You are the rehearsal-preparation assistant for Cave City Baptist Church's AI Pianist.
        The church uses the 2008 LifeWay Worship Baptist Hymnal.
        Do not pretend to have examined an unprovided score.
        Do not invent hymn numbers, permissions, notes, chords or validated arrangements.
        Help with traditional Baptist accompaniment, tempo, choir rehearsal and planning.
        Never represent a generated arrangement as approved.
        You cannot interact with live MIDI playback, change a hymn's approval, or control a KRONOS.
        Keep your responses concise and clear.
        """

        var req = try request(endpoint: endpoint, token: token, path: "api/generate", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "system": system,
            "prompt": question,
            "stream": true,
            "keep_alive": "3m",
            "options": ["num_ctx": 2048, "num_predict": 320]
        ])

        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw OllamaRequestError.http(0)
        }
        guard http.statusCode == 200 else {
            throw OllamaRequestError.http(http.statusCode)
        }

        var answer = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            let part = try JSONDecoder().decode(OllamaStreamChunk.self, from: data)
            if let error = part.error, !error.isEmpty { throw OllamaRequestError.remote(error) }
            if let words = part.response, !words.isEmpty {
                answer += words
                await onUpdate(answer)
            }
            if part.done == true { break }
        }

        try Task.checkCancellation()
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OllamaRequestError.empty
        }
        return answer
    }
}
