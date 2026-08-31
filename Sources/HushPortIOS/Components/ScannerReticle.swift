#if os(iOS)
import SwiftUI

struct ScannerReticle: View {
    let isActive: Bool
    @State private var scanProgress: CGFloat = -0.9

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width - 68, geometry.size.height * 0.39)
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height * 0.40

            ZStack {
                Color.black.opacity(0.34)
                    .mask {
                        Rectangle()
                            .overlay {
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .frame(width: side, height: side)
                                    .position(x: centerX, y: centerY)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
                    .frame(width: side, height: side)
                    .position(x: centerX, y: centerY)

                ScannerCorners()
                    .stroke(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: side, height: side)
                    .position(x: centerX, y: centerY)

                if isActive {
                    LinearGradient(
                        colors: [.clear, HushPortPalette.brandBright.opacity(0.95), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: side - 34, height: 2)
                    .shadow(color: HushPortPalette.brandBright.opacity(0.85), radius: 7)
                    .position(x: centerX, y: centerY + scanProgress * (side * 0.39))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.75).repeatForever(autoreverses: true)) {
                scanProgress = 0.9
            }
        }
    }
}
#endif
