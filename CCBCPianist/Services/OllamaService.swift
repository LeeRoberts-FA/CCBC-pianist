import Foundation
import Security

struct OllamaModelList: Decodable {
    struct Model: Decodable {
        let name: String
    }
    let models: [Model]
}

private struct OllamaChunk: Decodable {
    let response: String?
    let done: Bool?
    let error: String?
}

enum OllamaError: LocalizedError {
    case invalidEndpoint
    case insecureEndpoint
    case server(Int)
    case remote(String)
    case noAnswer
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Enter a full Ollama server URL, such as https://your-secure-server.example.com."
        case .insecureEndpoint:
            return "Use HTTPS for remote Ollama. Plain HTTP is only accepted on localhost through a private SSH/VPN tunnel; do not expose port 11434 to the internet."
        case .server(let status):
            return "Ollama server returned HTTP \(status). Check the address, API token and selected model."
        case .remote(let message):
            return "Ollama error: \(message)"
        case .noAnswer:
            return "The server returned no text. Try a smaller model or check its logs."
        case .keychain(let status):
            return "Unable to save the Ollama token to Keychain (status \(status))."
        }
    }
}

/// Ollama can run on this computer, or on a separate server using HTTPS.
/// Credentials never go to UserDefaults or version control.
enum OllamaConnection {
    static let defaultEndpoint = "http://127.0.0.1:11434"
    private static let endpointKey = "CCBCPianist.Ollama.Endpoint"
    private static let keychainService = "org.cavecitybaptist.ccbcaipianist.ollama"

    static func validate(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(),
              !host.isEmpty,
              parts.user == nil,
              parts.password == nil,
              parts.query == nil,
              parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              ["http", "https"].contains(scheme),
              let url = parts.url else {
            throw OllamaError.invalidEndpoint
        }
        if scheme == "http" &&
           !["localhost", "127.0.0.1", "::1"].contains(host) {
            throw OllamaError.insecureEndpoint
        }
        return url
    }

    static func savedEndpoint() -> String {
        UserDefaults.standard.string(forKey: endpointKey) ?? defaultEndpoint
    }

    static func loadToken(for endpoint: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: endpoint,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    static func save(endpoint: String, token: String) throws {
        let normalized = try validate(endpoint).absoluteString
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: normalized
        ]

        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            let entry: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: normalized,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecValueData as String: Data(value.utf8)
            ]
            // Add before deleting anything else; preserve the previous
            // value if a Keychain operation fails.
            let update: [String: Any] = [
                kSecValueData as String: Data(value.utf8)
            ]
            let outcome = SecItemUpdate(key as CFDictionary, update as CFDictionary)
            if outcome == errSecItemNotFound {
                let result = SecItemAdd(entry as CFDictionary, nil)
                guard result == errSecSuccess else { throw OllamaError.keychain(result) }
            } else if outcome != errSecSuccess {
                throw OllamaError.keychain(outcome)
            }
        } else {
            // Clearing the field intentionally clears the saved token.
            let result = SecItemDelete(key as CFDictionary)
            guard result == errSecSuccess || result == errSecItemNotFound else {
                throw OllamaError.keychain(result)
            }
        }
        UserDefaults.standard.set(normalized, forKey: endpointKey)
    }
}

struct OllamaService {
    private func makeRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanToken.isEmpty {
            request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func models(endpoint: String, token: String) async throws -> [String] {
        let base = try OllamaConnection.validate(endpoint)
        var request = makeRequest(url: base.appendingPathComponent("api/tags"), token: token)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OllamaError.server(status) }
        return try JSONDecoder().decode(OllamaModelList.self, from: data).models.map(\.name)
    }

    /// Streams answer tokens so a slow remote model does not leave the
    /// interface apparently frozen while waiting for a full response.
    /// Deliberately has no access to the live audio/MIDI subsystems.
    func ask(
        endpoint: String,
        token: String,
        model: String,
        question: String,
        onUpdate: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let base = try OllamaConnection.validate(endpoint)
        let system = """
        You are a preparation-only hymn assistant for Cave City Baptist Church.
        The church references the 2008 LifeWay Baptist Hymnal.
        Never claim to have inspected a score unless it was supplied.
        Do not fabricate hymn music, numbers, copyright permissions or verified arrangements.
        Provide concise help for traditional congregational singing and choir rehearsals.
        You cannot send MIDI, approve an imported arrangement or initiate music playback.
        """
        var request = makeRequest(url: base.appendingPathComponent("api/generate"), token: token)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "system": system,
            "prompt": question,
            "stream": true,
            "keep_alive": "3m",
            "options": [
                "num_ctx": 2048,
                "num_predict": 320,
                "temperature": 0.3
            ]
        ])
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OllamaError.server(status) }

        var whole = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.isEmpty { continue }
            let chunk = try JSONDecoder().decode(OllamaChunk.self, from: Data(line.utf8))
            if let error = chunk.error, !error.isEmpty {
                throw OllamaError.remote(error)
            }
            if let text = chunk.response, !text.isEmpty {
                whole += text
                await onUpdate(whole)
            }
            if chunk.done == true { break }
        }

        try Task.checkCancellation()
        guard !whole.isEmpty else { throw OllamaError.noAnswer }
        return whole
    }
}
