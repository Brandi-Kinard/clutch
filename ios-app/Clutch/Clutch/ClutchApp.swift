import SwiftUI

@main
struct ClutchApp: App {
    init() {
        DATManager.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
