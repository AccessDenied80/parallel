import SwiftUI
import AppKit

@main
struct ParallelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup("Parallel") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 440)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Додати застосунок…") { pickApps(store) }
                    .keyboardShortcut("o")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Потрібно, коли бінарник запускають напряму через `swift run`.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
func pickApps(_ store: Store) {
    let panel = NSOpenPanel()
    panel.title = "Оберіть застосунок"
    panel.allowedContentTypes = [.applicationBundle]
    panel.allowsMultipleSelection = true
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    if panel.runModal() == .OK {
        panel.urls.forEach(store.addApp(at:))
    }
}
