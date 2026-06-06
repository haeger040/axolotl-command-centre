import SwiftUI

struct CommandCentreView: View {
    @State private var selection: SidebarDestination = .explorer

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $selection)

            Divider()
                .overlay(Color.white.opacity(0.08))

            SelectedPage(destination: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 0.08, green: 0.09, blue: 0.10))
        .preferredColorScheme(.dark)
    }
}

private struct Sidebar: View {
    @Binding var selection: SidebarDestination

    var body: some View {
        VStack(spacing: 10) {
            ForEach(SidebarDestination.allCases) { destination in
                Button {
                    selection = destination
                } label: {
                    SidebarIcon(destination: destination, isSelected: selection == destination)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(destination.title)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 58)
        .padding(.top, 14)
        .background(Color(red: 0.11, green: 0.12, blue: 0.14))
    }
}

private struct SelectedPage: View {
    let destination: SidebarDestination

    var body: some View {
        switch destination {
        case .explorer:
            ExplorerView()
        case .qwenCode:
            QwenCodeView()
        case .claudeCode:
            AIComingSoonView(title: destination.title, assetName: "ClaudeLogo")
        case .openAICodex:
            AIComingSoonView(title: destination.title, assetName: "OpenAILogo")
        case .sourceControl:
            SourceControlView()
        case .terminal:
            TerminalView()
        case .settings:
            PageFallback(destination: destination)
        }
    }
}

private struct SidebarIcon: View {
    let destination: SidebarDestination
    let isSelected: Bool

    var body: some View {
        Group {
            if let assetName = destination.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .opacity(isSelected ? 1 : 0.58)
            } else {
                Image(systemName: destination.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.54))
            }
        }
        .frame(width: 44, height: 44)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.12))
            }
        }
        .contentShape(Rectangle())
    }
}

private struct AIComingSoonView: View {
    let title: String
    let assetName: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(height: 62)
            .padding(.horizontal, 16)
            .background(Color(red: 0.08, green: 0.09, blue: 0.10))

            Divider()
                .overlay(Color.white.opacity(0.08))

            Text("Coming soon")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct PageFallback: View {
    let destination: SidebarDestination

    var body: some View {
        Text("\(destination.title) page")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.top, 26)
    }
}

#Preview {
    CommandCentreView()
}
