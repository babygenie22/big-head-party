import SwiftUI

@main
struct BigHeadPartyApp: App {
    @StateObject private var store = CharacterStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.pink)
        }
    }
}

/// First launch: the intro/demo. After that: straight to the home screen.
struct RootView: View {
    @AppStorage("hasSeenIntro") private var hasSeenIntro = false

    var body: some View {
        if hasSeenIntro {
            HomeView()
        } else {
            IntroView { withAnimation(.spring) { hasSeenIntro = true } }
                .transition(.opacity)
        }
    }
}
