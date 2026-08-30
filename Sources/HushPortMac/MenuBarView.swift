#if os(macOS)
import SwiftUI

struct MenuBarView: View {
    @Bindable var session = MacSessionController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: session.menuBarIcon)
                Text("HushPort")
                    .font(.headline)
            }
            Text(session.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            LabeledContent("Paired iPhone", value: session.pairedPhoneName)
            if session.isSending {
                Button("Disconnect") { session.disconnect() }
                Button(session.isMuted ? "Unmute" : "Mute") { session.toggleMute() }
            } else {
                Button("Stream Mac audio") { session.connectAndStream() }
                    .disabled(session.currentStreamTarget() == nil)
                Button("Send test tone") { session.sendTestTone() }
                    .disabled(session.currentStreamTarget() == nil)
            }
            Divider()
            Button("Open Settings…") {
                HushPortAppActions.showMainWindow()
            }
            Button("Quit HushPort") { NSApplication.shared.terminate(nil) }
        }
        .padding()
        .frame(width: 260)
    }
}
#endif
