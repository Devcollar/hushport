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
                Text("Beta")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2), in: Capsule())
            }
            Text(session.streamingStatusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            LabeledContent("Paired iPhone", value: session.pairedPhoneName)
            if session.isSending {
                Button("Stop Streaming") { session.disconnect() }
                Button(session.isMuted ? "Unmute" : "Mute") { session.toggleMute() }
            } else {
                Button("Stream Mac audio") { session.connectAndStream() }
                    .disabled(!session.canStartStreaming)
                Button("Send test tone") { session.sendTestTone() }
                    .disabled(!session.canStartStreaming)
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
