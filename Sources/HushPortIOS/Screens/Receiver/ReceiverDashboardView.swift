#if os(iOS)
import HushPortCore
import SwiftUI

struct ReceiverDashboardView: View {
    @Bindable var model: ReceiverModel
    @Binding var showForgetConfirmation: Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 14) {
                    dashboardHeader
                    deviceCard
                    audioControlCard(availableHeight: geometry.size.height)
                    metricsStrip
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 18)
                .frame(
                    maxWidth: .infinity,
                    minHeight: geometry.size.height,
                    alignment: .top
                )
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
        }
    }

    private var dashboardHeader: some View {
        HStack(spacing: 11) {
            BrandMark(size: 42)

            Text("HushPort")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Beta")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.22), in: Capsule())

            Spacer(minLength: 10)

            ConnectionBadge(
                linkState: model.linkState,
                quality: model.connectionQuality
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private var deviceCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [HushPortPalette.brandBright, HushPortPalette.brand],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "laptopcomputer")
                    .font(.system(size: 31, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 70, height: 70)
            .shadow(color: HushPortPalette.brandBright.opacity(0.28), radius: 18, y: 8)

            VStack(alignment: .leading, spacing: 7) {
                Text(model.pairedMac?.name ?? "Mac")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Label("Paired securely", systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HushPortPalette.success)

                Text("This iPhone: \(model.localIPAddress)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            Menu {
                Button(role: .destructive) {
                    showForgetConfirmation = true
                } label: {
                    Label("Forget this Mac", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.055), in: Circle())
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            HushPortPalette.brandBright.opacity(0.13),
                            HushPortPalette.panel.opacity(0.96),
                            HushPortPalette.panel.opacity(0.96)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [HushPortPalette.brandBright.opacity(0.38), HushPortPalette.border],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private func audioControlCard(availableHeight: CGFloat) -> some View {
        let compact = availableHeight < 760
        let controlSize: CGFloat = compact ? 142 : 166

        return VStack(spacing: compact ? 15 : 18) {
            VStack(spacing: 6) {
                HStack(spacing: 9) {
                    Image(systemName: "waveform")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(HushPortPalette.brandBright)

                    Text("Audio Receiver")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Text(audioSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.57))
                    .multilineTextAlignment(.center)
            }

            ReceiverOrb(
                isListening: model.isListening,
                size: controlSize
            )
            .onTapGesture {
                model.isListening ? model.stopAudio() : model.startAudio()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(model.isListening ? "Stop Listening" : "Start Listening")

            VStack(spacing: 7) {
                Text(audioHeadline)
                    .font(.system(size: compact ? 24 : 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(audioStatusMessage)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 330)
            }

            Button {
                model.isListening ? model.stopAudio() : model.startAudio()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.isListening ? "stop.fill" : "play.fill")
                        .font(.subheadline.weight(.bold))
                    Text(model.isListening ? "Stop Listening" : "Start Listening")
                        .font(.headline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(primaryButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(
                    color: (model.isListening ? Color.red : HushPortPalette.brand).opacity(0.24),
                    radius: 18,
                    y: 8
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, compact ? 18 : 22)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            HushPortPalette.brand.opacity(0.09),
                            HushPortPalette.panel.opacity(0.98),
                            HushPortPalette.panel.opacity(0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            HushPortPalette.brand.opacity(0.68),
                            HushPortPalette.brandBright.opacity(0.18),
                            HushPortPalette.border
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        }
        .shadow(color: HushPortPalette.brand.opacity(0.10), radius: 28, y: 12)
    }

    @ViewBuilder
    private var primaryButtonBackground: some View {
        if model.isListening {
            LinearGradient(
                colors: [Color.red.opacity(0.95), Color.red.opacity(0.72)],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            LinearGradient(
                colors: [Color(red: 0.50, green: 0.20, blue: 1.00), HushPortPalette.brandBright],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var audioHeadline: String {
        if !model.isListening { return "Receiver is paused" }
        if model.status.localizedCaseInsensitiveContains("playing") { return "Audio is playing" }
        if model.status.localizedCaseInsensitiveContains("muted") { return "Muted by your Mac" }
        return "Ready for audio"
    }

    private var audioSubtitle: String {
        model.isListening ? "Receiving audio from your Mac" : "Ready to receive audio from your Mac"
    }

    private var audioStatusMessage: String {
        if model.status == "Stopped" {
            return "Tap Start Listening when you want audio on this iPhone."
        }
        if model.status == "Ready" {
            return "Tap Start Listening when you want audio on this iPhone."
        }
        if let guidance = model.connectionGuidance,
           model.isListening,
           (model.connectionQuality == .poor || model.connectionQuality == .fair) {
            return guidance
        }
        return model.status
    }

    private var metricsStrip: some View {
        HStack(spacing: 0) {
            DashboardMetric(
                icon: "waveform",
                title: "Packets",
                value: model.packetCount.formatted(),
                detail: model.playedPacketCount > 0
                    ? "\(model.playedPacketCount.formatted()) played"
                    : "Received",
                tint: HushPortPalette.brandBright
            )

            metricDivider

            DashboardMetric(
                icon: "square.stack.3d.up.fill",
                title: "Buffer",
                value: model.queuedPackets.formatted(),
                detail: "queued",
                tint: HushPortPalette.brand
            )

            metricDivider

            DashboardMetric(
                icon: connectionMetricIcon,
                title: "Connection",
                value: connectionMetricValue,
                detail: connectionMetricDetail,
                tint: connectionMetricTint
            )
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(HushPortPalette.panel.opacity(0.90), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(HushPortPalette.border, lineWidth: 1)
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1, height: 72)
    }

    private var connectionMetricValue: String {
        if model.isListening, model.connectionQuality != .unknown {
            return model.connectionQuality.displayName
        }
        if model.status.localizedCaseInsensitiveContains("playing") { return "Live" }
        if model.isListening { return "Ready" }
        return "Paired"
    }

    private var connectionMetricDetail: String {
        if let guidance = model.connectionGuidance, model.connectionQuality == .poor || model.connectionQuality == .fair {
            return "Wi-Fi"
        }
        return model.isListening ? "Listening" : "Secure"
    }

    private var connectionMetricIcon: String {
        model.isListening ? "wifi" : "checkmark.shield.fill"
    }

    private var connectionMetricTint: Color {
        switch model.connectionQuality {
        case .excellent, .good, .unknown:
            return HushPortPalette.success
        case .fair:
            return .orange
        case .poor:
            return Color(red: 0.95, green: 0.35, blue: 0.22)
        }
    }
}
#endif
