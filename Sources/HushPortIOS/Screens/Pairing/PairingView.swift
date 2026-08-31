#if os(iOS)
import SwiftUI

struct PairingView: View {
    @Bindable var model: ReceiverModel
    @Binding var showManualPairing: Bool

    var body: some View {
        ZStack {
            PairingScannerView(isScanningEnabled: scannerIsEnabled) { payload in
                model.pair(withScannedPayload: payload)
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    .black.opacity(0.72),
                    .clear,
                    .black.opacity(0.10),
                    .black.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScannerReticle(isActive: scannerIsEnabled)

            VStack(spacing: 0) {
                scannerHeader
                Spacer(minLength: 0)
                scannerBottomCard
            }
        }
    }

    private var scannerHeader: some View {
        VStack(spacing: 18) {
            HStack(spacing: 11) {
                BrandMark(size: 40)

                Text("HushPort")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Beta")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.18), in: Capsule())

                Spacer()

                Label("Secure", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.11), in: Capsule())
            }

            VStack(spacing: 7) {
                Text("Pair your Mac")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Scan the QR code shown in the HushPort Mac app.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var scannerBottomCard: some View {
        VStack(spacing: 15) {
            pairingStatusPill

            VStack(spacing: 5) {
                Text(isPairing ? "Connecting securely…" : "Center the QR code in the frame")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(isPairing
                     ? "Keep this screen open while your Mac confirms the request."
                     : "Pairing starts automatically when the QR code is recognized.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
            }

            Button {
                showManualPairing = true
            } label: {
                Label("Enter pairing details manually", systemImage: "keyboard")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [HushPortPalette.brand, HushPortPalette.brandBright],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isPairing)
            .opacity(isPairing ? 0.55 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
        .overlay(alignment: .top) {
            Capsule()
                .fill(.white.opacity(0.20))
                .frame(width: 38, height: 5)
                .padding(.top, 8)
        }
        .shadow(color: .black.opacity(0.30), radius: 30, y: -10)
        .ignoresSafeArea(edges: .bottom)
    }

    private var pairingStatusPill: some View {
        HStack(spacing: 8) {
            if isPairing {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Image(systemName: model.statusIcon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(model.statusColor)
            }

            Text(model.status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.30), in: Capsule())
    }

    private var isPairing: Bool {
        model.status.localizedCaseInsensitiveContains("pairing")
    }

    private var scannerIsEnabled: Bool {
        !isPairing
    }
}
#endif
