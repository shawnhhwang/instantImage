import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force the app to run as a regular GUI application.
        // Because we are building an executable target via SwiftPM (not an .app bundle),
        // macOS defaults to a background/accessory policy where the app cannot steal
        // focus from the terminal. This makes it become a normal windowed app.
        NSApp.setActivationPolicy(.regular)
        
        // Force our app to become the active (key) application.
        // This is critical when the app is launched from a terminal:
        // without this, the terminal retains keyboard focus and our
        // local event monitor never fires.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
        
        // Intercept culling arrow/control keys globally at app level.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // NOTE: We intentionally do NOT check NSApp.modalWindow here.
            // SwiftUI's NavigationSplitView and other internal components create
            // auxiliary/panel windows that register as modal windows, causing
            // NSApp.modalWindow to be non-nil even during normal photo browsing.
            // This was the root cause of arrow keys being silently dropped.
            
            // If Escape is pressed, always drop any active text focus and pass to shortcut handler
            if event.keyCode == 53 {
                DispatchQueue.main.async {
                    (event.window ?? NSApp.keyWindow)?.makeFirstResponder(nil)
                }
            } else if self.isEditingText(for: event) {
                return event
            }
            
            let shortcutKeys: Set<UInt16> = [
                123, // Left Arrow
                124, // Right Arrow
                126, // Up Arrow
                125, // Down Arrow
                49,  // Space
                53,  // Escape
                3,   // F key (FullScreen)
                36,  // Enter key (FullScreen)
                76,  // Keypad Enter
                6,   // Z key (Zoom Toggle)
                18,  // 1 key (Rating 1)
                19,  // 2 key (Rating 2)
                20,  // 3 key (Rating 3)
                21,  // 4 key (Rating 4)
                23,  // 5 key (Rating 5)
                29,  // 0 key (Clear Rating)
                17,  // T key (Tag Toggle)
                46,  // M key (Move to destination)
                37,  // L key (Loupe toggle)
                51,  // Delete key (Backspace)
                117, // Forward Delete key (Del)
                14,  // E key (Auto light)
                13,  // W key (Auto white balance)
                38,  // J key (Clipping warning)
                42,  // \ key (Before/After)
                8,   // C key (Copy settings)
                9,   // V key (Paste settings)
                44,  // ? / / key (Shortcut guide)
                34,  // I key (Inspector toggle)
                11,  // B key (Filmstrip toggle)
                1,   // S key (FaceSwap / Save)
                7,   // X key (Reject / Keep Original)
                4,   // H key (Fast Convert to HEIC & Delete Original)
                0,   // A key (Cmd+A: Select All)
                15   // R key (Review / FaceSwap Confirmation Mode)
            ]
            
            if shortcutKeys.contains(event.keyCode) {
                LoggerManager.shared.log("Captured global shortcut key: \(event.keyCode)", level: .debug)
                // Post event to NotificationCenter for main view model to consume
                NotificationCenter.default.post(
                    name: NSNotification.Name("didReceiveKeyboardEvent"),
                    object: nil,
                    userInfo: ["event": event]
                )
                return nil // Consume event so it doesn't reach other responders
            }
            
            return event
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func isEditingText(for event: NSEvent) -> Bool {
        guard let window = event.window ?? NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        guard let firstResponder = window.firstResponder else { return false }
        // Only block keyboard events if the user is genuinely editing inside an
        // active field editor NSTextView.
        if let textView = firstResponder as? NSTextView {
            return textView.isEditable && textView.isFieldEditor
        }
        return false
    }
}

@main
struct ProjectLuminaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1440, height: 900)
    }
}
