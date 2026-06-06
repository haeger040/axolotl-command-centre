import SwiftUI

@main
struct AxolotlCommandCentreApp: App {
    @AppStorage("hasUnlockedWelcome") private var hasUnlockedWelcome = false

    var body: some Scene {
        WindowGroup {
            if hasUnlockedWelcome {
                CommandCentreView()
            } else {
                WelcomeView {
                    hasUnlockedWelcome = true
                }
            }
        }
    }
}
