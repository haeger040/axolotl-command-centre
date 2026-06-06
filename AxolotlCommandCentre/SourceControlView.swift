import SwiftUI

struct SourceControlView: View {
    private let client = BackendClient()

    @State private var status: GitStatusResponse?
    @State private var selectedFile: GitFile?
    @State private var selectedDiff: GitDiffResponse?
    @State private var commitMessage = ""
    @State private var isLoading = true
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(Color.white.opacity(0.08))

            if let selectedFile {
                diffView(file: selectedFile)
            } else {
                statusView
            }
        }
        .task {
            await refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Source Control")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            if let status, status.behind > 0 || status.ahead > 0 {
                iconButton("arrow.triangle.2.circlepath", label: "Sync") {
                    await runCommand { try await client.syncGit() }
                }
            }

            iconButton("square.and.arrow.down", label: "Pull") {
                await runCommand { try await client.pullGit() }
            }

            iconButton("arrow.clockwise", label: "Refresh") {
                await refresh()
            }
        }
        .frame(height: 62)
        .padding(.horizontal, 16)
        .background(Color(red: 0.08, green: 0.09, blue: 0.10))
    }

    private var statusView: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                errorView(errorMessage)
            } else if let status {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        branchStrip(status)
                        commitBox(status)
                        fileSection("Conflicts", files: status.conflicted, action: .stage)
                        fileSection("Staged Changes", files: status.staged, action: .unstage)
                        fileSection("Changes", files: status.changes, action: .stage)
                        fileSection("Untracked", files: status.untracked, action: .stage)
                    }
                    .padding(16)
                }
            }
        }
    }

    private func branchStrip(_ status: GitStatusResponse) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.68))

            Text(status.branch)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)

            if status.behind > 0 {
                Text("↓ \(status.behind)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }

            if status.ahead > 0 {
                Text("↑ \(status.ahead)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }

    private func commitBox(_ status: GitStatusResponse) -> some View {
        VStack(spacing: 10) {
            TextField("Message", text: $commitMessage, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .lineLimit(2...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 10) {
                Button {
                    Task {
                        await runCommand { try await client.commitGit(message: commitMessage) }
                        commitMessage = ""
                    }
                } label: {
                    Text("Commit")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color(red: 0.34, green: 0.30, blue: 0.87), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isBusy || status.staged.isEmpty || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                iconButton("arrow.up", label: "Push") {
                    await runCommand { try await client.pushGit() }
                }
            }
        }
    }

    private func fileSection(_ title: String, files: [GitFile], action: FileAction) -> some View {
        Group {
            if !files.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(title) \(files.count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                            .textCase(.uppercase)

                        Spacer(minLength: 0)

                        if action == .stage {
                            sectionButton("plus") {
                                await runCommand { try await client.stageGitFiles(files.map(\.path)) }
                            }
                        } else {
                            sectionButton("minus") {
                                await runCommand { try await client.unstageGitFiles(files.map(\.path)) }
                            }
                        }
                    }

                    LazyVStack(spacing: 0) {
                        ForEach(files) { file in
                            GitFileRow(file: file, primaryAction: action) {
                                Task {
                                    await select(file)
                                }
                            } performPrimary: {
                                await perform(action, file: file)
                            } discard: {
                                await runCommand { try await client.discardGitFiles([file.path]) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func diffView(file: GitFile) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    selectedFile = nil
                    selectedDiff = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.path)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(file.staged ? "Staged diff" : "Working tree diff")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.48))
                }

                Spacer(minLength: 0)
            }
            .frame(height: 54)
            .padding(.horizontal, 12)

            Divider()
                .overlay(Color.white.opacity(0.08))

            if let errorMessage {
                errorView(errorMessage)
            } else if let selectedDiff {
                ScrollView([.vertical, .horizontal]) {
                    Text(selectedDiff.diff.isEmpty ? "No diff available" : selectedDiff.diff)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func iconButton(_ image: String, label: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Image(systemName: image)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(label)
    }

    private func sectionButton(_ image: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Image(systemName: image)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func errorView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 15))
            .foregroundStyle(.red.opacity(0.9))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            status = try await client.fetchGitStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func runCommand(_ command: () async throws -> GitCommandResponse) async {
        isBusy = true
        errorMessage = nil
        do {
            status = try await command().status
            if let selectedFile {
                await select(selectedFile)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }

    private func select(_ file: GitFile) async {
        selectedFile = file
        selectedDiff = nil
        errorMessage = nil
        do {
            selectedDiff = try await client.fetchGitDiff(path: file.path, staged: file.staged)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ action: FileAction, file: GitFile) async {
        switch action {
        case .stage:
            await runCommand { try await client.stageGitFiles([file.path]) }
        case .unstage:
            await runCommand { try await client.unstageGitFiles([file.path]) }
        }
    }
}

private enum FileAction {
    case stage
    case unstage
}

private struct GitFileRow: View {
    let file: GitFile
    let primaryAction: FileAction
    let open: () -> Void
    let performPrimary: () async -> Void
    let discard: () async -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text((file.path as NSString).lastPathComponent)
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)

                        Text((file.path as NSString).deletingLastPathComponent)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.42))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Text(statusBadge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(statusColor)
                        .frame(width: 18)
                }
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    await performPrimary()
                }
            } label: {
                Image(systemName: primaryAction == .stage ? "plus" : "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.76))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    await discard()
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.85))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 48)
        .contentShape(Rectangle())
    }

    private var icon: String {
        switch file.status {
        case "deleted":
            "doc.badge.minus"
        case "untracked", "added":
            "doc.badge.plus"
        default:
            "doc.text"
        }
    }

    private var statusBadge: String {
        switch file.status {
        case "modified":
            "M"
        case "added":
            "A"
        case "deleted":
            "D"
        case "renamed":
            "R"
        case "untracked":
            "U"
        case "conflict":
            "!"
        default:
            "•"
        }
    }

    private var statusColor: Color {
        switch file.status {
        case "untracked", "added":
            .green
        case "deleted", "conflict":
            .red
        default:
            .orange
        }
    }
}

#Preview {
    SourceControlView()
        .background(Color(red: 0.08, green: 0.09, blue: 0.10))
}
