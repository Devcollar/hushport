#if os(iOS)
import SwiftUI

struct ReceiverOrb: View {
    let isListening: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(HushPortPalette.brand.opacity(isListening ? 0.18 : 0.08))
                .frame(width: size, height: size)
                .blur(radius: 1)

            Circle()
                .stroke(HushPortPalette.brand.opacity(isListening ? 0.72 : 0.42), lineWidth: 3)
                .frame(width: size, height: size)
                .shadow(color: HushPortPalette.brand.opacity(isListening ? 0.65 : 0.22), radius: 18)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [HushPortPalette.brandBright, HushPortPalette.brand, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: size - 16, height: size - 16)
                .opacity(isListening ? 1 : 0.70)

            Circle()
                .fill(Color(red: 0.075, green: 0.072, blue: 0.12))
                .frame(width: size - 34, height: size - 34)

            Image(systemName: isListening ? "waveform" : "speaker.slash.fill")
                .font(.system(size: size * 0.25, weight: .semibold))
                .foregroundStyle(isListening ? Color.white : Color.white.opacity(0.72))
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isListening)
        }
        .frame(width: size + 10, height: size + 10)
        .contentShape(Circle())
    }
}
#endif
