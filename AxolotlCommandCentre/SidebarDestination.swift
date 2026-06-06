import SwiftUI

enum SidebarDestination: String, CaseIterable, Identifiable {
    case explorer
    case sourceControl
    case qwenCode
    case claudeCode
    case openAICodex
    case terminal
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .explorer:
            "Explorer"
        case .sourceControl:
            "Source Control"
        case .qwenCode:
            "Qwen Code"
        case .claudeCode:
            "Claude Code"
        case .openAICodex:
            "OpenAI Codex"
        case .terminal:
            "Terminal"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .explorer:
            "folder"
        case .sourceControl:
            "point.3.connected.trianglepath.dotted"
        case .qwenCode:
            ""
        case .claudeCode:
            ""
        case .openAICodex:
            ""
        case .terminal:
            "terminal"
        case .settings:
            "gearshape"
        }
    }

    var assetName: String? {
        switch self {
        case .qwenCode:
            "QwenLogo"
        case .claudeCode:
            "ClaudeLogo"
        case .openAICodex:
            "OpenAILogo"
        default:
            nil
        }
    }
}
