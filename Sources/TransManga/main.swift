import SwiftUI
import AppKit
import Carbon

extension Notification.Name {
    static let transMangaTranslate = Notification.Name("transMangaTranslate")
    static let transMangaToggleClickThrough = Notification.Name("transMangaToggleClickThrough")
    static let transMangaToggleAutoWatch = Notification.Name("transMangaToggleAutoWatch")
    static let transMangaToggleCards = Notification.Name("transMangaToggleCards")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var translateHotKeyRef: EventHotKeyRef?
    private var clickThroughHotKeyRef: EventHotKeyRef?
    private var autoWatchHotKeyRef: EventHotKeyRef?
    private var peekCardsHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let overlayController = OverlayWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let cwdIconURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("AppIcon.png")
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "png")
            ?? (FileManager.default.fileExists(atPath: cwdIconURL.path) ? cwdIconURL : nil),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }

        registerGlobalHotKey()
        // Overlay starts OFF on launch; toggling store.isVisible shows/hides it.
    }

    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let event = event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            DispatchQueue.main.async {
                switch hotKeyID.id {
                case 1:
                    NotificationCenter.default.post(name: .transMangaTranslate, object: nil)
                case 2:
                    NotificationCenter.default.post(name: .transMangaToggleClickThrough, object: nil)
                case 3:
                    NotificationCenter.default.post(name: .transMangaToggleAutoWatch, object: nil)
                case 4:
                    NotificationCenter.default.post(name: .transMangaToggleCards, object: nil)
                default:
                    break
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        let modifiers = UInt32(controlKey | optionKey)

        let translateID = EventHotKeyID(signature: OSType(0x544D4731), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_M), modifiers, translateID, GetApplicationEventTarget(), 0, &translateHotKeyRef)

        let clickThroughID = EventHotKeyID(signature: OSType(0x544D4732), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_O), modifiers, clickThroughID, GetApplicationEventTarget(), 0, &clickThroughHotKeyRef)

        let autoWatchID = EventHotKeyID(signature: OSType(0x544D4733), id: 3)
        RegisterEventHotKey(UInt32(kVK_ANSI_W), modifiers, autoWatchID, GetApplicationEventTarget(), 0, &autoWatchHotKeyRef)

        let peekID = EventHotKeyID(signature: OSType(0x544D4734), id: 4)
        RegisterEventHotKey(UInt32(kVK_ANSI_H), modifiers, peekID, GetApplicationEventTarget(), 0, &peekCardsHotKeyRef)
    }
}

@main
struct TransMangaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("TransManga") {
            ContentView()
        }
    }
}
