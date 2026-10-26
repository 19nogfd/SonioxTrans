import SwiftUI

@main
struct SonioxTransApp: App {
    @StateObject private var history = HistoryStore()
    @StateObject private var session = TranslationSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(history)
                .environmentObject(session)
                .onAppear { session.history = history }
        }
    }
}
