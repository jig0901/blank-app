import SwiftUI

@main
struct PulseApp: App {
    @StateObject private var store = PulseStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
