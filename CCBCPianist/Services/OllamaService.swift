import Foundation

struct OllamaModelList: Decodable {
    struct Model: Decodable {
        let name: String
    }
    let models: [Model]
}

struct OllamaResponse: Decodable {
    let response: String
}

enum OllamaError: LocalizedError {
    case server(Int)
    var errorDescription: String? {
        switch self {
        case .server(let code): return "Local Ollama returned HTTP \(code)."
        }
    }
}

struct OllamaService {
    private let base = URL(string: "http://127.0.0.1:11434")!

    func models() async throws -> [String] {
        var request = URLRequest(url: base.appendingPathComponent("api/tags"))
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OllamaError.server(status) }
        return try JSONDecoder().decode(OllamaModelList.self, from: data).models.map(\.name)
    }

    func ask(model: String, question: String) async throws -> String {
        let system = """
        You are the preparation-only assistant for Cave City Baptist Church's AI Pianist.
        The church references the 2008 LifeWay Baptist Hymnal.
        Do not claim to have inspected a hymn score unless it was supplied.
        Do not invent hymn numbers, musical notes, permissions, or validated arrangements.
        Give practical traditional Baptist congregation accompaniment advice.
        You have no access to piano or MIDI output, cannot approve imports, and cannot start playback.
        """
        var request = URLRequest(url: base.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "system": system,
            "prompt": question,
            "stream": false
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw OllamaError.server(status) }
        return try JSONDecoder().decode(OllamaResponse.self, from: data).response
    }
}
