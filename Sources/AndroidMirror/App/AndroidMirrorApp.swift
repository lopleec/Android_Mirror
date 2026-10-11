import SwiftUI
import AppKit

@main
struct AndroidMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = MirrorStore()

    var body: some Scene {
        WindowGroup(L10n.tr("Android Mirror"), id: "mirror") {
            ContentView(store: store)
                .onAppear { delegate.store = store; store.begin() }
        }
        .defaultSize(width: 374, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands { MirrorCommands(store: store) }
        Settings { SettingsView(store: store) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: MirrorStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let cleanup = store?.shutdown() else { return .terminateNow }
        Task {
            await cleanup.value
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
