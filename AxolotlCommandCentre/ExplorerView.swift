import SwiftUI

struct ExplorerView: View {
    private let client = BackendClient()

    @State private var rootPath = ""
    @State private var entries: [ExplorerEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 15))
                    .foregroundStyle(.red.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            ExplorerRow(entry: entry)
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
}

private struct ExplorerRow: View {
    let entry: ExplorerEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.kind == .directory ? "folder" : "doc.text")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(entry.kind == .directory ? Color.cyan : Color.white.opacity(0.72))
                .frame(width: 20)

            Text(entry.name)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .frame(height: 38)
        .contentShape(Rectangle())
    }
}

#Preview {
    ExplorerView()
        .background(Color(red: 0.08, green: 0.09, blue: 0.10))
}
