import Foundation
import Security

struct OllamaModelList: Decodable {
    struct Model: Decodable { let name: String }
    let models: [Model]
}

struct OllamaStreamChunk: Decodable {
    let response: String?
    let done: Bool?
    let error: String?
}

enum OllamaError: LocalizedError {
    case invalidServer
    case insecureServer
    case server(Int, String)
    case emptyResponse
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidServer:
            return "Enter a valid Ollama server URL, such as https://piano.example.com or http://127.0.0.1:11435."
        case .insecureServer:
            return "Remote Ollama needs HTTPS. For a private computer, use a secure VPN/SSH tunnel and connect to http://127.0.0.1:11435 instead. Never expose port 11434 publicly."
        case .server(let code, let body):
            return "Ollama returned HTTP \(code). \(body)"
        case .emptyResponse:
            return "The model returned no answer. Try a smaller model or check the server logs."
        case .keychain(let code):
            return "Could not access macOS Keychain (status \(code))."
        }
    }
}

/// The URL is saved in UserDefaults. An optional remote API token is stored in
/// macOS Keychain, never in source control or UserDefaults.
enum OllamaConnection {
    static let defaultsKey = "CCBCPianist.OllamaEndpoint"
    static let defaultEndpoint = "http://127.0.0.1:11434"
    private static let keychainService = "org.cavecitybaptist.ccbcaipianist.ollama"

    static func endpointURL(_ text: String) throws -> URL {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(),
              !host.isEmpty,
              parts.user == nil,
              parts.password == nil,
              parts.query == nil,
              parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              let url = parts.url else {
            throw OllamaError.invalidServer
        }

        guard scheme == "https" || scheme == "http" else {
            throw OllamaError.invalidServer
        }
        // Plain HTTP is only supported through loopback, including an SSH
        // forward to another machine. A public, unauthenticated Ollama
        // endpoint is a serious security risk.
        if scheme == "http" && !["127.0.0.1", "localhost", "::1"].contains(host) {
            throw OllamaError.insecureServer
        }
        return url
    }

    static func savedEndpoint() -> String {
        UserDefaults.standard.string(forKey: defaultsKey) ?? defaultEndpoint
    }

    static func loadToken(for endpoint: String) -> String {
        guard !endpoint.isEmpty else { return "" }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: endpoint,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return ""
        }
        return token
    }

    static func save(endpoint: String, token: String) throws {
        let normalized = try endpointURL(endpoint).absoluteString
        let credential = token.trimmingCharacters(in: .whitespacesAndNewlines)

        let filter: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: normalized
        ]
        if !credential.isEmpty {
            let newEntry: [String: Any] = filter.merging([
                kSecValueData as String: Data(credential.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]) { _, value in value }
            SecItemDelete(filter as CFDictionary)
            let status = SecItemAdd(newEntry as CFDictionary, nil)
            guard status == errSecSuccess else { throw OllamaError.keychain(status) }
        } else {
            SecItemDelete(filter as CFDictionary)
        }

        UserDefaults.standard.set(normalized, forKey: defaultsKey)
    }
}

struct OllamaService {
    private func buildURL(endpoint: String, path: String) throws -> URL {
        let base = try OllamaConnection.endpointURL(endpoint)
        return base.appendingPathComponent(path)
    }

    private func request(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let key = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func models(endpoint: String, token: String) async throws -> [String] {
        let url = try buildURL(endpoint: endpoint, path: "api/tags")
        var req = request(url: url, token: token)
        req.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let body = String(decoding: data.prefix(250), as: UTF8.self)
            throw OllamaError.server(status, body)
        }
        return try JSONDecoder().decode(OllamaModelList.self, from: data).models.map(\.name)
    }

    /// Stream model output while it is generated, rather than holding the UI
    /// for a complete response that may take several minutes to arrive.
    ///
    /// The assistant has no reference to any MIDI or playback objects.
    func ask(
        endpoint: String,
        token: String,
        model: String,
        question: String,
        onUpdate: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let url = try buildURL(endpoint: endpoint, path: "api/generate")
        let system = """
        You are the preparation-only assistant for Cave City Baptist Church's AI Pianist.
        The church references the 2008 LifeWay Baptist Hymnal.
        Do not claim to have inspected a hymn score unless it was supplied.
        Do not invent hymn numbers, notes, permissions, or approved arrangements.
        Give concise, practical advice about traditional congregational accompaniment.
        You have no access to piano or MIDI output, cannot approve imports, and cannot start playback.
        """
        var req = request(url: url, token: token)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "system": system,
            "prompt": question,
            "stream": true,
            "options": [
                "num_predict": 384,
                "num_ctx": 2048,
                "temperature": 0.3
            ]
        ])

        let (stream, response) = try await URLSession.shared.bytes(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw OllamaError.server(status, "Check the server address, selected model and API key.")
        }

        var output = ""
        for try await line in stream.lines {
            try Task.checkCancellation()
            guard !line.isEmpty else { continue }
            let chunk = try JSONDecoder().decode(OllamaStreamChunk.self, from: Data(line.utf8))
            if let message = chunk.error, !message.isEmpty {
                throw OllamaError.server(200, message)
            }
            if let fragment = chunk.response, !fragment.isEmpty {
                output += fragment
                await onUpdate(output)
            }
            if chunk.done == true { break }
        }
        guard !output.isEmpty else { throw OllamaError.emptyResponse }
        return output
    }
}
