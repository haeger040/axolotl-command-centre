import Foundation

struct BackendClient {
    var baseURL = URL(string: "http://10.10.11.214:8000")!

    func fetchExplorer() async throws -> ExplorerResponse {
        let url = baseURL.appending(path: "explorer")
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw BackendError.unexpectedResponse
        }

        return try JSONDecoder().decode(ExplorerResponse.self, from: data)
    }
}

enum BackendError: Error, LocalizedError {
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            "The backend returned an unexpected response."
        }
    }
}

struct ExplorerResponse: Decodable {
    let root: String
    let entries: [ExplorerEntry]
}

struct ExplorerEntry: Decodable, Identifiable {
    let name: String
    let path: String
    let kind: EntryKind

    var id: String { path }
}

enum EntryKind: String, Decodable {
    case directory
    case file
}
