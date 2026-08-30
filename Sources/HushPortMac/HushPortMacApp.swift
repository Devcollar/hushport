#if os(macOS)
import AppKit
import HushPortCore
import SwiftUI

extension Notification.Name {
    static let hushportOpenMainWindow = Notification.Name("hushportOpenMainWindow")
}

@main
struct HushPortMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowRoot()
        }
        .defaultSize(width: 480, height: 620)

        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: "speaker.wave.2.fill")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MainWindowRoot: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SenderView()
            .onReceive(NotificationCenter.default.publisher(for: .hushportOpenMainWindow)) { _ in
                openWindow(id: "main")
                HushPortAppActions.showMainWindow()
            }
    }
}

@MainActor
enum HushPortAppActions {
    static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
        NotificationCenter.default.post(name: .hushportOpenMainWindow, object: nil)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            HushPortAppActions.showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        HushPortAppActions.showMainWindow()
        return true
    }
}
#else
@main enum HushPortMacApp { static func main() {} }
#endif
