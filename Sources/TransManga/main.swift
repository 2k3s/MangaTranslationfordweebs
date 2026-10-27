import SwiftUI
import AppKit
import Carbon.HIToolbox

@main
struct TransManga: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 640, minHeight: 540)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyRef: EventHotKeyRef?
    private var clickThroughHotKeyRef: EventHotKeyRef?
    private var autoWatchHotKeyRef: EventHotKeyRef?
    private var peekCardsHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let overlayController = OverlayWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        if let icon = NSImage(named: "AppIcon")
                 ?? NSImage(contentsOfFile: "AppIcon.png") {
                 NSApp.applicationIconImage = icon
             }
        
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }

        registerGlobalHotKey()
        overlayController.show()

        NotificationCenter.default.addObserver(
            forName: .transMangaToggleClickThrough,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.overlayController.toggleClickThrough()
        }
    }

    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
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
                        NotificationCenter.default.post(
                            name: .transMangaTranslate,
                            object: nil
                        )
                    case 2:
                        NotificationCenter.default.post(
                            name: .transMangaToggleClickThrough,
                            object: nil
                        )
                    case 3:
                        NotificationCenter.default.post(
                            name: .transMangaToggleAutoWatch,
                            object: nil
                        )
                    case 4:
                        NotificationCenter.default.post(
                            name: .transMangaToggleCards,
                            object: nil
                        )
                    default:
                        break
                    }
                }

                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            print("Failed to install hotkey handler: \(installStatus)")
            return
        }

        let signature = OSType(0x4D544657)

        let translateID = EventHotKeyID(signature: signature, id: 1)
        let translateStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            UInt32(controlKey | optionKey),
            translateID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        let clickThroughID = EventHotKeyID(signature: signature, id: 2)
        let clickThroughStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_O),
            UInt32(controlKey | optionKey),
            clickThroughID,
            GetApplicationEventTarget(),
            0,
            &clickThroughHotKeyRef
        )

        let autoWatchID = EventHotKeyID(signature: signature, id: 3)
        let autoWatchStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_W),
            UInt32(controlKey | optionKey),
            autoWatchID,
            GetApplicationEventTarget(),
            0,
            &autoWatchHotKeyRef
        )

        let peekCardsID = EventHotKeyID(signature: signature, id: 4)
        let peekCardsStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_H),
            UInt32(controlKey | optionKey),
            peekCardsID,
            GetApplicationEventTarget(),
            0,
            &peekCardsHotKeyRef
        )

        print("M hotkey status: \(translateStatus)")
        print("O hotkey status: \(clickThroughStatus)")
        print("W hotkey status: \(autoWatchStatus)")
        print("H hotkey status: \(peekCardsStatus)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let clickThroughHotKeyRef {
            UnregisterEventHotKey(clickThroughHotKeyRef)
        }
        if let autoWatchHotKeyRef {
            UnregisterEventHotKey(autoWatchHotKeyRef)
        }
        if let peekCardsHotKeyRef {
            UnregisterEventHotKey(peekCardsHotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}

extension Notification.Name {
    static let transMangaTranslate =
        Notification.Name("TransMangaTranslate")
    static let transMangaToggleClickThrough =
        Notification.Name("TransMangaToggleClickThrough")
    static let transMangaToggleAutoWatch =
        Notification.Name("TransMangaToggleAutoWatch")
    static let transMangaToggleCards =
        Notification.Name("TransMangaToggleCards")
}
