import SwiftUI

struct ExplorerView: View {
    private let client = BackendClient()

    @State private var rootPath = ""
    @State private var entries: [ExplorerEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedFile: FileContentResponse?
    @State private var draftContent = ""
    @State private var isEditingFile = false
    @State private var isFileLoading = false
    @State private var isSavingFile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedFile {
                FileEditorView(
                    file: selectedFile,
                    draftContent: $draftContent,
                    isEditing: $isEditingFile,
                    isSaving: isSavingFile,
                    errorMessage: errorMessage,
                    onBack: closeFile,
                    onSave: {
                        Task {
                            await saveSelectedFile()
                        }
                    }
                )
            } else {
                header

                if isLoading || isFileLoading {
                    ProgressView()
                        .controlSize(.regular)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    errorText(errorMessage)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(entries) { entry in
                                ExplorerRow(entry: entry) {
                                    Task {
                                        await open(entry)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .task {
            await loadEntries()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Explorer")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)

            Text(rootPath.isEmpty ? "/Users/jules/Documents/testrepo1234" : rootPath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func errorText(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 15))
            .foregroundStyle(.red.opacity(0.9))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func loadEntries() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await client.fetchExplorer()
            rootPath = response.root
            entries = response.entries
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func open(_ entry: ExplorerEntry) async {
        guard entry.kind == .file else { return }
        isFileLoading = true
        errorMessage = nil

        do {
            let file = try await client.fetchFile(path: entry.path)
            selectedFile = file
            draftContent = file.content
            isEditingFile = false
        } catch {
            errorMessage = error.localizedDescription
        }

        isFileLoading = false
    }

    private func closeFile() {
        selectedFile = nil
        draftContent = ""
        isEditingFile = false
        errorMessage = nil
    }

    private func saveSelectedFile() async {
        guard let selectedFile else { return }
        isSavingFile = true
        errorMessage = nil

        do {
            let savedFile = try await client.saveFile(path: selectedFile.path, content: draftContent)
            self.selectedFile = savedFile
            draftContent = savedFile.content
            isEditingFile = false
        } catch {
            errorMessage = error.localizedDescription
        }

        isSavingFile = false
    }
}

private struct FileEditorView: View {
    let file: FileContentResponse
    @Binding var draftContent: String
    @Binding var isEditing: Bool
    let isSaving: Bool
    let errorMessage: String?
    let onBack: () -> Void
    let onSave: () -> Void

    private var hasChanges: Bool {
        draftContent != file.content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(file.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isEditing {
                    Button(action: onSave) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(hasChanges && !isSaving ? .white : .white.opacity(0.35))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasChanges || isSaving)
                    .accessibilityLabel("Save")
                } else {
                    Button {
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit")
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red.opacity(0.9))
            }

            if isEditing {
                TextEditor(text: $draftContent)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                ScrollView {
                    Text(file.content.isEmpty ? "Empty file" : file.content)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(file.content.isEmpty ? .white.opacity(0.42) : .white.opacity(0.88))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }
}

private struct ExplorerRow: View {
    let entry: ExplorerEntry
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.kind == .directory ? "folder" : "doc.text")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(entry.kind == .directory ? Color.cyan : Color.white.opacity(0.72))
                .frame(width: 20)

            Text(entry.name)
                .font(.system(size: 15))
                .foregroundStyle(entry.kind == .directory ? .white.opacity(0.55) : .white.opacity(0.88))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .frame(height: 38)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

#Preview {
    ExplorerView()
        .background(Color(red: 0.08, green: 0.09, blue: 0.10))
}
