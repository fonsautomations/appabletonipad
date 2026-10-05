import SwiftUI
import UIKit

@main
struct StageDeckApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(store.live)
                .environmentObject(store.sequencer)
                .environmentObject(store.midi)
                .environmentObject(store.control)
                .preferredColorScheme(.dark)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    if store.profile.autoReconnect { store.connect() }
                }
        }
    }
}
