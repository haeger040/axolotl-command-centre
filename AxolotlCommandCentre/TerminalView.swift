import SwiftUI
import UIKit

struct TerminalView: View {
    private let client = BackendClient()

    @State private var terminals: [TerminalSummary] = []
    @State private var selectedID: String?
    @State private var output = ""
    @State private var socket: URLSessionWebSocketTask?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(Color.white.opacity(0.08))

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 15))
                    .foregroundStyle(.red.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
            } else {
                TerminalTextSurface(text: output) { input in
                    send(input)
                }
            }
        }
        .task {
            await load()
        }
        .onDisappear {
            socket?.cancel(with: .goingAway, reason: nil)
            socket = nil
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(terminals) { terminal in
                        Button {
                            attach(to: terminal.id)
                        } label: {
                            Text(terminal.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selectedID == terminal.id ? .white : .white.opacity(0.62))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(
                                    selectedID == terminal.id ? Color.white.opacity(0.14) : Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                Task {
                    await newTerminal()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New terminal")
        }
        .frame(height: 56)
        .padding(.horizontal, 10)
        .background(Color(red: 0.08, green: 0.09, blue: 0.10))
    }

    private func load() async {
        isLoading = true
        errorMessage = nil

        do {
            var loaded = try await client.fetchTerminals().terminals
            if loaded.isEmpty {
                let terminal = try await client.createTerminal()
                loaded = [terminal]
            }
            terminals = loaded
            if selectedID == nil, let first = loaded.first {
                attach(to: first.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func newTerminal() async {
        do {
            let terminal = try await client.createTerminal()
            terminals.append(terminal)
            attach(to: terminal.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attach(to id: String) {
        selectedID = id
        output = ""
        socket?.cancel(with: .goingAway, reason: nil)

        let task = URLSession.shared.webSocketTask(with: client.terminalWebSocketURL(id: id))
        socket = task
        task.resume()
        receiveLoop(task)

        Task {
            _ = try? await client.resizeTerminal(id: id, cols: 80, rows: 24)
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { result in
            switch result {
            case .success(let message):
                if case .string(let string) = message,
                   let data = string.data(using: .utf8),
                   let event = try? JSONDecoder().decode(TerminalSocketEvent.self, from: data),
                   event.type == "output" {
                    DispatchQueue.main.async {
                        output.append(event.data ?? "")
                        if output.count > 120_000 {
                            output.removeFirst(output.count - 100_000)
                        }
                    }
                }
                receiveLoop(task)
            case .failure(let error):
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func send(_ input: String) {
        guard let socket else { return }
        let event = TerminalSocketEvent(type: "input", data: input)
        guard let data = try? JSONEncoder().encode(event),
              let string = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(string)) { error in
            if let error {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct TerminalSocketEvent: Codable {
    let type: String
    let data: String?
}

private struct TerminalTextSurface: UIViewRepresentable {
    let text: String
    let onInput: (String) -> Void

    func makeUIView(context: Context) -> TerminalUITextView {
        let view = TerminalUITextView()
        view.backgroundColor = UIColor(red: 0.03, green: 0.035, blue: 0.04, alpha: 1)
        view.textColor = .white
        view.tintColor = .white
        view.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.keyboardType = .asciiCapable
        view.alwaysBounceVertical = true
        view.delegate = context.coordinator
        view.inputHandler = onInput
        return view
    }

    func updateUIView(_ uiView: TerminalUITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            let bottom = NSRange(location: max(uiView.text.count - 1, 0), length: 1)
            uiView.scrollRangeToVisible(bottom)
        }
        uiView.inputHandler = onInput
        if !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard let terminalView = textView as? TerminalUITextView else { return false }
            if text.isEmpty {
                terminalView.inputHandler?("\u{7f}")
            } else {
                terminalView.inputHandler?(text == "\n" ? "\r" : text)
            }
            return false
        }
    }
}

private final class TerminalUITextView: UITextView {
    var inputHandler: ((String) -> Void)?

    override var canBecomeFirstResponder: Bool {
        true
    }
}

#Preview {
    TerminalView()
        .background(Color.black)
}
