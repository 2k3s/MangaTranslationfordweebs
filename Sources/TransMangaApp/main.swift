import SwiftUI
import TransMangaCore

@main
struct TransMangaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("TransManga") {
            ContentView()
        }

        MenuBarExtra("TransManga", systemImage: "cat.fill") {
            MenuBarControlView()
        }
    }
}
