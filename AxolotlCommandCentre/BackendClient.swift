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

    func fetchQwenChats() async throws -> QwenChatsResponse {
        let url = baseURL.appending(path: "qwen/chats")
        return try await get(url)
    }

    func createQwenChat() async throws -> QwenChat {
        let url = baseURL.appending(path: "qwen/chats")
        return try await post(url, body: QwenCreateChatRequest(prompt: nil))
    }

    func fetchQwenChat(id: String) async throws -> QwenChat {
        let url = baseURL.appending(path: "qwen/chats/\(id)")
        return try await get(url)
    }

    func sendQwenMessage(chatID: String, prompt: String) async throws -> QwenChat {
        let url = baseURL.appending(path: "qwen/chats/\(chatID)/messages")
        return try await post(url, body: QwenSendMessageRequest(prompt: prompt))
    }

    func fetchGitStatus() async throws -> GitStatusResponse {
        let url = baseURL.appending(path: "git/status")
        return try await get(url)
    }

    func fetchGitDiff(path: String, staged: Bool) async throws -> GitDiffResponse {
        var components = URLComponents(url: baseURL.appending(path: "git/diff"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "staged", value: staged ? "true" : "false"),
        ]
        return try await get(components.url!)
    }

    func stageGitFiles(_ paths: [String]) async throws -> GitCommandResponse {
        try await post(baseURL.appending(path: "git/stage"), body: GitPathsRequest(paths: paths))
    }

    func unstageGitFiles(_ paths: [String]) async throws -> GitCommandResponse {
        try await post(baseURL.appending(path: "git/unstage"), body: GitPathsRequest(paths: paths))
    }

    func discardGitFiles(_ paths: [String]) async throws -> GitCommandResponse {
        try await post(baseURL.appending(path: "git/discard"), body: GitPathsRequest(paths: paths))
    }

    func commitGit(message: String) async throws -> GitCommandResponse {
        try await post(baseURL.appending(path: "git/commit"), body: GitCommitRequest(message: message))
    }

    func fetchGit() async throws -> GitCommandResponse {
        try await post(baseURL.appending(path: "git/fetch"), body: EmptyRequest())
    }

    func pullGit() async throws -> GitCommandResponse {
        try await post(baseURL.appending(path: "git/pull"), body: EmptyRequest())
    }

    func pushGit() async throws -> GitCommandResponse {
        try await post(baseURL.appending(path: "git/push"), body: EmptyRequest())
    }

    func syncGit() async throws -> GitCommandResponse {
        try await post(baseURL.appending(path: "git/sync"), body: EmptyRequest())
    }

    func fetchTerminals() async throws -> TerminalListResponse {
        try await get(baseURL.appending(path: "terminals"))
    }

    func createTerminal() async throws -> TerminalSummary {
        try await post(baseURL.appending(path: "terminals"), body: TerminalCreateRequest(title: nil, cwd: nil))
    }

    func resizeTerminal(id: String, cols: Int, rows: Int) async throws -> TerminalSummary {
        try await post(baseURL.appending(path: "terminals/\(id)/resize"), body: TerminalResizeRequest(cols: cols, rows: rows))
    }

    func terminalWebSocketURL(id: String) -> URL {
        var components = URLComponents(url: baseURL.appending(path: "terminals/\(id)/ws"), resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        return components.url!
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable, Body: Encodable>(_ url: URL, body: Body) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.unexpectedResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let detail = try? JSONDecoder().decode(BackendErrorResponse.self, from: data)
            throw BackendError.server(detail?.detail ?? "HTTP \(httpResponse.statusCode)")
        }
    }
}

enum BackendError: Error, LocalizedError {
    case unexpectedResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            "The backend returned an unexpected response."
        case .server(let message):
            message
        }
    }
}

private struct BackendErrorResponse: Decodable {
    let detail: String
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

struct QwenChatsResponse: Decodable {
    let chats: [QwenChatSummary]
}

struct QwenChatSummary: Decodable, Identifiable {
    let id: String
    let title: String
    let workspace: String
    let createdAt: String
    let updatedAt: String
    let messageCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case workspace
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case messageCount = "message_count"
    }
}

struct QwenChat: Decodable, Identifiable {
    let id: String
    let title: String
    let workspace: String
    let createdAt: String
    let updatedAt: String
    let messages: [QwenMessage]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case workspace
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case messages
    }
}

struct QwenMessage: Decodable, Identifiable {
    let id: String
    let role: QwenMessageRole
    let content: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt = "created_at"
    }
}

enum QwenMessageRole: String, Decodable {
    case user
    case assistant
}

private struct QwenCreateChatRequest: Encodable {
    let prompt: String?
}

private struct QwenSendMessageRequest: Encodable {
    let prompt: String
}

struct GitStatusResponse: Decodable {
    let root: String
    let branch: String
    let upstream: String?
    let ahead: Int
    let behind: Int
    let staged: [GitFile]
    let changes: [GitFile]
    let untracked: [GitFile]
    let conflicted: [GitFile]
}

struct GitFile: Decodable, Identifiable, Hashable {
    let path: String
    let indexStatus: String
    let worktreeStatus: String
    let status: String
    let staged: Bool
    let conflicted: Bool

    var id: String { "\(staged)-\(path)-\(indexStatus)-\(worktreeStatus)" }

    enum CodingKeys: String, CodingKey {
        case path
        case indexStatus = "index_status"
        case worktreeStatus = "worktree_status"
        case status
        case staged
        case conflicted
    }
}

struct GitDiffResponse: Decodable {
    let path: String
    let staged: Bool
    let diff: String
}

struct GitCommandResponse: Decodable {
    let status: GitStatusResponse
    let output: String
}

private struct GitPathsRequest: Encodable {
    let paths: [String]
}

private struct GitCommitRequest: Encodable {
    let message: String
}

private struct EmptyRequest: Encodable {}

struct TerminalListResponse: Decodable {
    let terminals: [TerminalSummary]
}

struct TerminalSummary: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let cwd: String
    let createdAt: String
    let alive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case cwd
        case createdAt = "created_at"
        case alive
    }
}

private struct TerminalCreateRequest: Encodable {
    let title: String?
    let cwd: String?
}

private struct TerminalResizeRequest: Encodable {
    let cols: Int
    let rows: Int
}
