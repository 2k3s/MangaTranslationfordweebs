import SwiftUI
import AppKit

@main
struct MangaLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 620, minHeight: 480)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prototype shortcut: Control + Option + M.
        // macOS may require Accessibility permission for global key monitoring.
        hotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 46, // M
                  event.modifierFlags.contains([.control, .option]) else { return }
            NotificationCenter.default.post(name: .mangaLensTranslate, object: nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyMonitor {
            NSEvent.removeMonitor(hotKeyMonitor)
        }
    }
}

extension Notification.Name {
    static let mangaLensTranslate = Notification.Name("MangaLensTranslate")
}
