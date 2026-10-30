import SwiftUI
import AppKit
import Carbon

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var translateHotKeyRef: EventHotKeyRef?
    private var clickThroughHotKeyRef: EventHotKeyRef?
    private var autoWatchHotKeyRef: EventHotKeyRef?
    private var peekCardsHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let overlayController = OverlayWindowController()

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let iconImage = MascotIconLoader.loadAppIcon() {
            NSApp.applicationIconImage = iconImage
        }

        registerGlobalHotKey()
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

public struct MenuBarControlView: View {
    @ObservedObject var store = OverlaySelectionStore.shared

    public init() {}

    public var body: some View {
        Toggle("Translation Box ON", isOn: $store.isVisible)

        Divider()

        Button("Translate Now (⌃⌥M)") {
            if !store.isVisible {
                store.isVisible = true
            }
            store.onTranslateRequested?()
        }

        Toggle("Auto-Watch Mode (⌃⌥W)", isOn: Binding(
            get: { store.isAutoWatching },
            set: { _ in store.onToggleAutoWatch?() }
        ))

        Toggle("Reading Lock / Click-Through (⌃⌥O)", isOn: Binding(
            get: { store.isClickThrough },
            set: { _ in store.onToggleClickThrough?() }
        ))

        Toggle("Show Translated Bubbles (⌃⌥H)", isOn: $store.showTranslationCards)

        Divider()

        Picker("Ollama Model", selection: $store.selectedModel) {
            ForEach(store.availableModels, id: \.self) { modelName in
                Text(modelName).tag(modelName)
            }
        }

        Button("Refresh Ollama Models") {
            store.onRefreshModelsRequested?()
        }

        Divider()

        Button("Show TransManga Window") {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where !(window is NSPanel) {
                window.makeKeyAndOrderFront(nil)
            }
        }

        Button("Quit TransManga") {
            NSApplication.shared.terminate(nil)
        }
    }
}
