import SwiftUI

struct ExplorerView: View {
    private let client = BackendClient()

    @State private var rootPath = ""
    @State private var entriesByFolder: [String: [ExplorerEntry]] = [:]
    @State private var expandedFolders: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedFile: FileContentResponse?
    @State private var draftContent = ""
    @State private var isEditingFile = false
    @State private var isFileLoading = false
    @State private var isSavingFile = false
    @State private var createKind: EntryKind?
    @State private var createName = ""
    @State private var createParentPath = ""
    @State private var isCreateAlertPresented = false
    @State private var renameTarget: ExplorerEntry?
    @State private var renameName = ""
    @State private var isRenameAlertPresented = false
    @State private var deleteTarget: ExplorerEntry?
    @State private var isDeleteDialogPresented = false
    @State private var copiedEntry: ExplorerEntry?

    private var rootEntries: [ExplorerEntry] {
        entriesByFolder[rootPath] ?? []
    }

    private var visibleRows: [ExplorerVisibleRow] {
        var rows: [ExplorerVisibleRow] = []
        appendVisibleRows(rootEntries, depth: 0, rows: &rows)
        return rows
    }

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
                            ForEach(visibleRows) { row in
                                ExplorerRow(
                                    entry: row.entry,
                                    depth: row.depth,
                                    isExpanded: expandedFolders.contains(row.entry.path),
                                    canPaste: row.entry.kind == .directory && copiedEntry != nil,
                                    onTap: {
                                        Task {
                                            await open(row.entry)
                                        }
                                    },
                                    onNewFile: {
                                        beginCreate(kind: .file, parentPath: row.entry.path)
                                    },
                                    onNewFolder: {
                                        beginCreate(kind: .directory, parentPath: row.entry.path)
                                    },
                                    onRename: {
                                        renameTarget = row.entry
                                        renameName = row.entry.name
                                        isRenameAlertPresented = true
                                    },
                                    onCopy: {
                                        copiedEntry = row.entry
                                    },
                                    onPaste: {
                                        Task {
                                            await paste(into: row.entry.path)
                                        }
                                    },
                                    onDelete: {
                                        deleteTarget = row.entry
                                        isDeleteDialogPresented = true
                                    }
                                )
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
            await loadRoot()
        }
        .alert(createTitle, isPresented: $isCreateAlertPresented) {
            TextField("Name", text: $createName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) {
                clearCreateState()
            }
            Button("Create") {
                let kind = createKind
                let parentPath = createParentPath
                let name = createName
                Task {
                    await createEntry(kind: kind, parentPath: parentPath, name: name)
                }
            }
        }
        .alert("Rename", isPresented: $isRenameAlertPresented) {
            TextField("Name", text: $renameName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) {
                clearRenameState()
            }
            Button("Rename") {
                let target = renameTarget
                let name = renameName
                Task {
                    await renameEntry(target: target, name: name)
                }
            }
        }
        .confirmationDialog("Delete this item?", isPresented: $isDeleteDialogPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let target = deleteTarget
                Task {
                    await deleteEntry(target: target)
                }
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
                isDeleteDialogPresented = false
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Explorer")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)

                Text(rootPath.isEmpty ? "/Users/jules/Documents/testrepo1234" : rootPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button {
                beginCreate(kind: .file, parentPath: rootPath)
            } label: {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New file")

            Button {
                beginCreate(kind: .directory, parentPath: rootPath)
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New folder")
        }
    }

    private var createTitle: String {
        createKind == .directory ? "New Folder" : "New File"
    }

    @ViewBuilder
    private func errorText(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 15))
            .foregroundStyle(.red.opacity(0.9))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func loadRoot() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await client.fetchExplorer()
            rootPath = response.root
            entriesByFolder[response.root] = response.entries
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func reloadFolder(_ path: String) async {
        do {
            let response = try await client.fetchExplorer(path: path)
            if path == rootPath || rootPath.isEmpty {
                rootPath = response.root
            }
            entriesByFolder[response.root] = response.entries
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func open(_ entry: ExplorerEntry) async {
        errorMessage = nil

        if entry.kind == .directory {
            if expandedFolders.contains(entry.path) {
                expandedFolders.remove(entry.path)
            } else {
                if entriesByFolder[entry.path] == nil {
                    await reloadFolder(entry.path)
                }
                expandedFolders.insert(entry.path)
            }
            return
        }

        isFileLoading = true
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

    private func beginCreate(kind: EntryKind, parentPath: String) {
        createKind = kind
        createParentPath = parentPath.isEmpty ? rootPath : parentPath
        createName = ""
        isCreateAlertPresented = true
    }

    private func createEntry(kind: EntryKind?, parentPath: String, name: String) async {
        guard let kind else { return }
        let parentPath = parentPath.isEmpty ? rootPath : parentPath
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil

        do {
            if kind == .directory {
                _ = try await client.createFolder(parentPath: parentPath, name: name)
                expandedFolders.insert(parentPath)
            } else {
                _ = try await client.createFile(parentPath: parentPath, name: name)
            }
            await reloadFolder(parentPath)
        } catch {
            errorMessage = error.localizedDescription
        }

        clearCreateState()
    }

    private func renameEntry(target: ExplorerEntry?, name: String) async {
        guard let target else { return }
        let parent = parentPath(for: target.path)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasExpanded = expandedFolders.contains(target.path)
        errorMessage = nil

        do {
            let renamed = try await client.renamePath(path: target.path, name: name)
            expandedFolders.remove(target.path)
            if target.kind == .directory, wasExpanded {
                expandedFolders.insert(renamed.path)
                entriesByFolder[renamed.path] = entriesByFolder.removeValue(forKey: target.path)
            }
            if selectedFile?.path == target.path {
                selectedFile = try await client.fetchFile(path: renamed.path)
                draftContent = selectedFile?.content ?? ""
            }
            await reloadFolder(parent)
        } catch {
            errorMessage = error.localizedDescription
        }

        clearRenameState()
    }

    private func paste(into destinationFolder: String) async {
        guard let copiedEntry else { return }
        errorMessage = nil

        do {
            _ = try await client.copyPath(sourcePath: copiedEntry.path, destinationFolder: destinationFolder)
            expandedFolders.insert(destinationFolder)
            await reloadFolder(destinationFolder)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteEntry(target: ExplorerEntry?) async {
        guard let target else { return }
        let parent = parentPath(for: target.path)
        errorMessage = nil

        do {
            try await client.deletePath(target.path)
            if selectedFile?.path == target.path {
                closeFile()
            }
            if copiedEntry?.path == target.path {
                copiedEntry = nil
            }
            expandedFolders.remove(target.path)
            entriesByFolder.removeValue(forKey: target.path)
            await reloadFolder(parent)
        } catch {
            errorMessage = error.localizedDescription
        }

        deleteTarget = nil
        isDeleteDialogPresented = false
    }

    private func clearCreateState() {
        createKind = nil
        createName = ""
        createParentPath = ""
        isCreateAlertPresented = false
    }

    private func clearRenameState() {
        renameTarget = nil
        renameName = ""
        isRenameAlertPresented = false
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

    private func parentPath(for path: String) -> String {
        guard let slashIndex = path.lastIndex(of: "/") else { return rootPath }
        let parent = String(path[..<slashIndex])
        return parent.isEmpty ? rootPath : parent
    }

    private func appendVisibleRows(_ entries: [ExplorerEntry], depth: Int, rows: inout [ExplorerVisibleRow]) {
        for entry in entries {
            rows.append(ExplorerVisibleRow(entry: entry, depth: depth))
            if entry.kind == .directory, expandedFolders.contains(entry.path) {
                appendVisibleRows(entriesByFolder[entry.path] ?? [], depth: depth + 1, rows: &rows)
            }
        }
    }
}

private struct ExplorerVisibleRow: Identifiable {
    let entry: ExplorerEntry
    let depth: Int

    var id: String { entry.path }
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
    let depth: Int
    let isExpanded: Bool
    let canPaste: Bool
    let onTap: () -> Void
    let onNewFile: () -> Void
    let onNewFolder: () -> Void
    let onRename: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if entry.kind == .directory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 14)
            } else {
                Color.clear.frame(width: 14)
            }

            Image(systemName: entry.kind == .directory ? "folder" : "doc.text")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(entry.kind == .directory ? Color.cyan : Color.white.opacity(0.72))
                .frame(width: 20)

            Text(entry.name)
                .font(.system(size: 15))
                .foregroundStyle(entry.kind == .directory ? .white.opacity(0.78) : .white.opacity(0.88))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 14)
        .frame(height: 38)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            if entry.kind == .directory {
                Button(action: onNewFile) {
                    Label("New File", systemImage: "doc.badge.plus")
                }
                Button(action: onNewFolder) {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                if canPaste {
                    Button(action: onPaste) {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                }
            }

            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    ExplorerView()
        .background(Color(red: 0.08, green: 0.09, blue: 0.10))
}
