import SwiftUI

struct QwenCodeView: View {
    private let client = BackendClient()

    @State private var chats: [QwenChatSummary] = []
    @State private var selectedChatID: String?
    @State private var selectedChat: QwenChat?
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(Color.white.opacity(0.08))

            if let selectedChat {
                chatDetail(selectedChat)
            } else {
                chatList
            }
        }
        .task {
            await loadChats()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                selectedChat = nil
                selectedChatID = nil
            } label: {
                Image("QwenLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Text(selectedChat?.title ?? "Qwen Code")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                Task {
                    await createChat()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(isSending)
            .accessibilityLabel("New Qwen chat")
        }
        .frame(height: 62)
        .padding(.horizontal, 16)
        .background(Color(red: 0.08, green: 0.09, blue: 0.10))
    }

    private var chatList: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                errorView(errorMessage)
            } else if chats.isEmpty {
                Text("No Qwen chats yet")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(chats) { chat in
                            Button {
                                Task {
                                    await selectChat(chat.id)
                                }
                            } label: {
                                QwenChatRow(chat: chat)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private func chatDetail(_ chat: QwenChat) -> some View {
        VStack(spacing: 0) {
            if chat.messages.isEmpty && !isSending {
                Text("Ask Qwen Code about this workspace")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(chat.messages) { message in
                                QwenMessageBubble(message: message)
                                    .id(message.id)
                            }

                            if isSending {
                                QwenWorkingBubble()
                                    .id("qwen-working")
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: chat.messages.count) {
                        scrollToLatest(in: proxy, chat: chat)
                    }
                    .onChange(of: isSending) {
                        scrollToLatest(in: proxy, chat: chat)
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            composer
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message Qwen", text: $draft, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            Button {
                Task {
                    await sendMessage()
                }
            } label: {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 34, height: 34)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color(red: 0.34, green: 0.30, blue: 0.87), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .buttonStyle(.plain)
            .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send message")
        }
        .padding(12)
        .background(Color(red: 0.08, green: 0.09, blue: 0.10))
    }

    private func errorView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 15))
            .foregroundStyle(.red.opacity(0.9))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
    }

    private func loadChats() async {
        isLoading = true
        errorMessage = nil

        do {
            chats = try await client.fetchQwenChats().chats
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func createChat() async {
        errorMessage = nil

        do {
            let chat = try await client.createQwenChat()
            selectedChatID = chat.id
            selectedChat = chat
            await loadChats()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectChat(_ id: String) async {
        errorMessage = nil

        do {
            selectedChatID = id
            selectedChat = try await client.fetchQwenChat(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendMessage() async {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        if selectedChatID == nil {
            await createChat()
        }

        guard let selectedChatID else { return }

        draft = ""
        isSending = true
        errorMessage = nil

        do {
            let optimisticMessage = QwenMessage(
                id: UUID().uuidString,
                role: .user,
                content: prompt,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )

            if let currentChat = selectedChat {
                selectedChat = currentChat.appendingMessage(optimisticMessage)
            }

            selectedChat = try await client.sendQwenMessage(chatID: selectedChatID, prompt: prompt)
            await loadChats()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

    private func scrollToLatest(in proxy: ScrollViewProxy, chat: QwenChat) {
        let targetID = isSending ? "qwen-working" : chat.messages.last?.id
        guard let targetID else { return }

        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(targetID, anchor: .bottom)
            }
        }
    }
}

private struct QwenChatRow: View {
    let chat: QwenChatSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(chat.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text("\(chat.messageCount) messages")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct QwenMessageBubble: View {
    let message: QwenMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 34)
            }

            Text(message.content)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))

            if message.role == .assistant {
                Spacer(minLength: 34)
            }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            Color(red: 0.34, green: 0.30, blue: 0.87).opacity(0.88)
        case .assistant:
            Color.white.opacity(0.08)
        }
    }
}

private struct QwenWorkingBubble: View {
    var body: some View {
        HStack {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.72))

                Text("Qwen is working")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            Spacer(minLength: 34)
        }
    }
}

private extension QwenChat {
    func appendingMessage(_ message: QwenMessage) -> QwenChat {
        QwenChat(
            id: id,
            title: title,
            workspace: workspace,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messages: messages + [message]
        )
    }
}

#Preview {
    QwenCodeView()
        .background(Color(red: 0.08, green: 0.09, blue: 0.10))
}
