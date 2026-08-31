#if os(iOS)
import HushPortCore
import SwiftUI

struct ConnectionBadge: View {
    let linkState: ReceiverLinkState
    let quality: StreamConnectionQuality

    private var label: String {
        switch linkState {
        case .streaming: quality == .unknown ? "Streaming" : quality.displayName
        case .listening: "Listening"
        case .reconnecting: "Reconnecting"
        case .networkUnavailable: "No Wi-Fi"
        case .waitingForMac: "Waiting for Mac"
        case .paired: "Paired"
        }
    }

    private var tint: Color {
        switch linkState {
        case .streaming:
            switch quality {
            case .excellent, .good, .unknown: HushPortPalette.success
            case .fair: .orange
            case .poor: Color(red: 0.95, green: 0.35, blue: 0.22)
            }
        case .listening, .paired: HushPortPalette.cyan
        case .reconnecting, .waitingForMac: .orange
        case .networkUnavailable: Color(red: 0.95, green: 0.35, blue: 0.22)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .shadow(color: tint.opacity(0.55), radius: 5)

            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.90))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.white.opacity(0.055), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }
}
#endif
