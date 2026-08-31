#if os(iOS)
import SwiftUI

struct BrandMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.15, blue: 0.38),
                            Color(red: 0.12, green: 0.10, blue: 0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [HushPortPalette.brandBright.opacity(0.55), HushPortPalette.brand.opacity(0.26)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            Image(systemName: "waveform")
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: HushPortPalette.brand.opacity(0.22), radius: 10, y: 4)
    }
}
#endif
