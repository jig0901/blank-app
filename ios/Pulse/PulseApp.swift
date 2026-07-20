import SwiftUI

@main
struct PulseApp: App {
    @StateObject private var store = PulseStore()

    var body: some Scene {
        WindowGroup {
            CommandCenterView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
