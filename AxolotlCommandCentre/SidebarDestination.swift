import SwiftUI

enum SidebarDestination: String, CaseIterable, Identifiable {
    case explorer
    case sourceControl
    case qwenCode
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
        case .terminal:
            "terminal"
        case .settings:
            "gearshape"
        }
    }
}
