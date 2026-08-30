#if os(iOS)
import AVFAudio
import HushPortCore
import Network
import SwiftUI
import UIKit

private enum HushPortPalette {
    static let brand = Color(red: 0.42, green: 0.29, blue: 1.00)
    static let brandBright = Color(red: 0.25, green: 0.47, blue: 1.00)
    static let cyan = Color(red: 0.20, green: 0.76, blue: 1.00)
    static let success = Color(red: 0.18, green: 0.78, blue: 0.49)
    static let background = Color(red: 0.018, green: 0.025, blue: 0.055)
    static let panel = Color(red: 0.055, green: 0.065, blue: 0.095)
    static let panelRaised = Color(red: 0.075, green: 0.085, blue: 0.12)
    static let border = Color.white.opacity(0.09)
}

struct ReceiverView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = ReceiverModel()
    @State private var showManualPairing = false
    @State private var showForgetConfirmation = false

    var body: some View {
        ZStack {
            appBackground

            if model.pairedMac == nil {
                unpairedScreen
                    .transition(.opacity)
            } else {
                pairedScreen
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.keyboard)
        .tint(HushPortPalette.brand)
        .animation(.easeInOut(duration: 0.25), value: model.pairedMac?.id)
        .sheet(isPresented: $showManualPairing) {
            ManualPairingSheet(model: model, isPresented: $showManualPairing)
        }
        .confirmationDialog(
            "Forget this Mac?",
            isPresented: $showForgetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Forget Pairing", role: .destructive) {
                model.forgetPairing()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’ll need to scan the QR code again before this iPhone can receive audio from the Mac.")
        }
        .onAppear { model.onAppear() }
        .onChange(of: scenePhase) { _, phase in
            model.handleScenePhase(phase)
        }
    }

    // MARK: - Full-screen background

    private var appBackground: some View {
        ZStack {
            HushPortPalette.background

            RadialGradient(
                colors: [HushPortPalette.brand.opacity(0.20), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 470
            )

            RadialGradient(
                colors: [HushPortPalette.brandBright.opacity(0.10), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Unpaired

    private var unpairedScreen: some View {
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

    // MARK: - Paired dashboard

    private var pairedScreen: some View {
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

// MARK: - Supporting views

private struct BrandMark: View {
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

private struct ConnectionBadge: View {
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

enum ReceiverLinkState: Equatable {
    case paired
    case listening
    case waitingForMac
    case streaming
    case reconnecting
    case networkUnavailable
}

private struct ReceiverOrb: View {
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

private struct DashboardMetric: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(title == "Connection" ? tint : .white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.40))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ScannerReticle: View {
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

private struct ScannerCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.17
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}

private struct ManualPairingSheet: View {
    @Bindable var model: ReceiverModel
    @Binding var isPresented: Bool
    @FocusState private var focusedField: Field?

    private enum Field {
        case code, address
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    BrandMark(size: 62)

                    VStack(spacing: 5) {
                        Text("Pair manually")
                            .font(.title2.bold())
                        Text("Enter the pairing details shown in the HushPort Mac app.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 0) {
                        LabeledPairingField(
                            icon: "number",
                            title: "Pairing code",
                            placeholder: "6-digit code",
                            text: $model.manualPairingCode,
                            keyboardType: .numberPad
                        )
                        .focused($focusedField, equals: .code)

                        Divider().padding(.leading, 48)

                        LabeledPairingField(
                            icon: "network",
                            title: "Mac address",
                            placeholder: "Network address",
                            text: $model.manualMacAddress,
                            keyboardType: .default
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .address)
                    }
                    .padding(.horizontal, 14)
                    .background(HushPortPalette.panelRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Button {
                        model.pairManually()
                        isPresented = false
                    } label: {
                        Label("Pair with Mac", systemImage: "link")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                LinearGradient(
                                    colors: [HushPortPalette.brand, HushPortPalette.brandBright],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canPairManually)
                    .opacity(model.canPairManually ? 1 : 0.45)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Manual Pairing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
            .onAppear { focusedField = .code }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

private struct LabeledPairingField: View {
    let icon: String
    let title: String
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HushPortPalette.brandBright)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: $text)
                    .font(.body.weight(.medium))
                    .keyboardType(keyboardType)
                    .textContentType(title == "Pairing code" ? .oneTimeCode : .none)
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Model

@MainActor @Observable
final class ReceiverModel {
    var port = Int(HushPortConstants.audioPort)
    var isListening = false
    var status = "Ready"
    var packetCount = 0
    var playedPacketCount = 0
    var pairedMac: TrustedDevice?
    var bufferDepth = HushPortConstants.defaultPrebufferPackets
    var queuedPackets = 0
    var connectionQuality: StreamConnectionQuality = .unknown
    var connectionGuidance: String?
    var linkState: ReceiverLinkState = .paired
    var manualPairingCode = ""
    var manualMacAddress = ""
    var localIPAddress = NetworkAddress.localIPv4Address() ?? "No Wi-Fi IP"

    private let identity: DeviceIdentity
    private let playbackEngine = IOSAudioPlaybackEngine()
    private var receiver: UDPAudioReceiver?
    private var controlReceiver: ControlChannelReceiver?
    private var audioTask: Task<Void, Never>?
    private var controlTask: Task<Void, Never>?
    private var pairTask: Task<Void, Never>?
    private var playbackBuffer = AdaptivePlaybackBuffer()
    private var pendingPlaybackPayload: Data?
    private var packetsSinceUIUpdate = 0
    private let networkMonitor = IOSNetworkPathMonitor()
    private var networkUsesWiFi = true
    private var lastNetworkSignature = ""
    private var linkWatchdog: Task<Void, Never>?
    private var playbackPump: Task<Void, Never>?
    private var macHeartbeat: Task<Void, Never>?
    private var lastPacketReceivedAt: ContinuousClock.Instant?
    private var isRestartingAfterNetworkChange = false
    private var pendingPairMacID: UUID?
    private var pendingPairMacAddress: String?
    private var pairingContinuation: CheckedContinuation<TrustedDevice, Error>?
    private var sessionObservers: [NSObjectProtocol] = []
    private var audioOutputIssue: String?

    var canPairManually: Bool {
        PairingCodeGenerator.isValid(manualPairingCode) && !manualMacAddress.isEmpty
    }

    var statusIcon: String {
        if status.contains("Pairing") { return "arrow.triangle.2.circlepath" }
        if status.contains("Playing") { return "waveform" }
        if status.contains("Waiting") || status.contains("Scan") { return "qrcode.viewfinder" }
        if status.contains("Paired") { return "checkmark.circle.fill" }
        if status.contains("timeout") || status.contains("rejected") || status.contains("Invalid") {
            return "exclamationmark.triangle.fill"
        }
        return isListening ? "antenna.radiowaves.left.and.right" : "circle"
    }

    var statusColor: Color {
        if status.contains("Playing") { return .green }
        if status.contains("timeout") || status.contains("rejected") || status.contains("Invalid") {
            return .orange
        }
        if status.contains("Paired") { return .green }
        return .accentColor
    }

    init() {
        identity = DeviceIdentityStore.load(defaultName: UIDevice.current.name)
        pairedMac = TrustedDeviceStore.primary()
        playbackEngine.onNeedsMoreAudio = { [weak self] in
            self?.drainReadyPayloads()
        }
        networkMonitor.onUpdate = { [weak self] snapshot in
            self?.applyNetworkSnapshot(snapshot)
        }
        networkMonitor.start()
    }

    func onAppear() {
        ensureControlChannel()
        registerAudioSessionObservers()
        guard pairedMac != nil else {
            status = "Scan Mac QR code"
            linkState = .paired
            return
        }
        linkState = isListening ? .listening : .paired
        if isListening {
            resumePlaybackIfNeeded()
            Task { await signalReceiverReadyToMac() }
        } else {
            startAudio()
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard isListening else { return }
        switch phase {
        case .background, .inactive:
            try? playbackEngine.prepareForBackground()
        case .active:
            resumePlaybackIfNeeded()
        @unknown default:
            break
        }
    }

    private func resumePlaybackIfNeeded() {
        do {
            try playbackEngine.ensurePlaying()
            audioOutputIssue = nil
            drainReadyPayloads()
            refreshStatusMessage()
        } catch {
            audioOutputIssue = Self.friendlyAudioError(error)
            refreshStatusMessage()
        }
    }

    private func refreshStatusMessage() {
        if playedPacketCount > 0 {
            status = "Playing"
            linkState = .streaming
            return
        }
        if packetCount > 0 {
            if let audioOutputIssue {
                status = "Receiving from \(pairedMac?.name ?? "Mac"). \(audioOutputIssue)"
            } else {
                status = "Receiving from \(pairedMac?.name ?? "Mac")"
            }
            linkState = .listening
            return
        }
        if linkState == .networkUnavailable {
            status = "Wi-Fi unavailable — waiting for network"
            return
        }
        if linkState == .reconnecting {
            status = "Network changed — reconnecting…"
            return
        }
        let macName = pairedMac?.name ?? "Mac"
        if let audioOutputIssue {
            status = "Waiting for \(macName). \(audioOutputIssue)"
        } else {
            status = "Waiting for \(macName)…"
        }
        linkState = isListening ? .waitingForMac : .paired
    }

    private func registerAudioSessionObservers() {
        guard sessionObservers.isEmpty else { return }

        sessionObservers.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: nil
            ) { [weak self] notification in
                let isEnding: Bool
                if let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                   let type = AVAudioSession.InterruptionType(rawValue: typeValue) {
                    isEnding = type == .ended
                } else {
                    isEnding = false
                }
                guard isEnding else { return }
                Task { @MainActor [weak self] in
                    self?.resumePlaybackIfNeeded()
                }
            }
        )

        sessionObservers.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.silenceSecondaryAudioHintNotification,
                object: AVAudioSession.sharedInstance(),
                queue: nil
            ) { [weak self] notification in
                let otherAppStopped: Bool
                if let hintValue = notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt {
                    otherAppStopped = hintValue == AVAudioSession.SilenceSecondaryAudioHintType.end.rawValue
                } else {
                    otherAppStopped = false
                }
                guard otherAppStopped else { return }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(200))
                    self?.resumePlaybackIfNeeded()
                }
            }
        )
    }

    func forgetPairing() {
        let macHost = pairedMac?.networkAddress
        stopAudio()
        pairTask?.cancel()
        pairTask = nil
        pairingContinuation = nil
        pendingPairMacID = nil
        pendingPairMacAddress = nil
        TrustedDeviceStore.clear()
        pairedMac = nil
        linkState = .paired
        connectionQuality = .unknown
        status = "Scan Mac QR code"
        if let macHost, !macHost.isEmpty {
            Task { await notifyMacUnpair(at: macHost) }
        }
    }

    private func notifyMacUnpair(at host: String) async {
        do {
            let sender = try ControlChannelSender(host: host)
            try await sender.prepare()
            try await sender.send(
                ControlMessage(
                    type: .unpair,
                    senderID: identity.id,
                    senderName: identity.name
                )
            )
            sender.cancel()
        } catch {
            // Mac may already be offline.
        }
    }

    func pair(withScannedPayload payload: String) {
        guard let offer = PairingPayload.parse(payload) else {
            status = "Invalid QR code"
            return
        }
        pair(with: offer)
    }

    func pairManually() {
        let offer = MacPairingOffer(
            deviceID: UUID(),
            deviceName: "Mac",
            pairingCode: manualPairingCode,
            hostAddress: manualMacAddress
        )
        pair(with: offer, validateDeviceID: false)
    }

    func pair(with offer: MacPairingOffer, validateDeviceID: Bool = true) {
        pairTask?.cancel()
        pairTask = Task {
            ensureControlChannel()
            pendingPairMacID = validateDeviceID ? offer.deviceID : nil
            pendingPairMacAddress = offer.hostAddress
            status = "Pairing…"
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(12))
                if pairingContinuation != nil {
                    failPairing(with: PairingClientError.timeout)
                    pendingPairMacID = nil
                    pendingPairMacAddress = nil
                    status = PairingClientError.timeout.localizedDescription
                }
            }
            defer { timeoutTask.cancel() }
            do {
                let trusted = try await waitForPairingResult(for: offer)
                TrustedDeviceStore.save(trusted)
                pairedMac = trusted
                pendingPairMacID = nil
                pendingPairMacAddress = nil
                manualPairingCode = ""
                manualMacAddress = ""
                status = "Paired with \(trusted.name)"
                startAudio()
            } catch is CancellationError {
            } catch let error as PairingClientError {
                pendingPairMacID = nil
                status = error.localizedDescription
            } catch {
                pendingPairMacID = nil
                status = error.localizedDescription
            }
        }
    }

    func startAudio() {
        guard !isListening else { return }
        audioOutputIssue = nil
        guard let port = UInt16(exactly: port) else {
            status = "Invalid port"
            return
        }

        Task {
            await startAudioAsync(port: port)
        }
    }

    private func startAudioAsync(port: UInt16) async {
        do {
            try await startNetworkListener(port: port)
            startLinkWatchdog()
            refreshStatusMessage()
            await signalReceiverReadyToMac()
        } catch {
            status = error.localizedDescription
        }
    }

    private func signalReceiverReadyToMac() async {
        guard let host = pairedMac?.networkAddress, !host.isEmpty else { return }
        do {
            let sender = try ControlChannelSender(host: host)
            try await sender.prepare()
            try await sender.send(
                ControlMessage(
                    type: .pong,
                    senderID: identity.id,
                    senderName: identity.name,
                    networkAddress: NetworkAddress.localIPv4Address()
                )
            )
            sender.cancel()
        } catch {
            // Mac may not be streaming yet; ping on stream start will wake playback.
        }
    }

    private func startNetworkListener(port: UInt16) async throws {
        let receiver = try UDPAudioReceiver(
            port: port,
            serviceName: identity.name,
            deviceID: identity.id,
            preferWiFi: true
        )
        try await receiver.prepare()
        self.receiver = receiver
        isListening = true
        linkState = .listening
        playbackBuffer.reset()
        pendingPlaybackPayload = nil
        packetsSinceUIUpdate = 0
        playbackEngine.setScheduleAheadLimit(24)
        connectionQuality = .unknown
        connectionGuidance = nil
        packetCount = 0
        playedPacketCount = 0
        startPlaybackPump()
        startMacHeartbeat()
        audioTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                for try await packet in receiver.packets {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        self.handleIncomingPacket(packet)
                    }
                }
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        self.status = error.localizedDescription
                    }
                }
            }
            await MainActor.run {
                self.stopAudio(keepStatus: true)
            }
        }
    }

    private func startMacHeartbeat() {
        macHeartbeat?.cancel()
        macHeartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, isListening, pairedMac != nil else { continue }
                await signalReceiverReadyToMac()
            }
        }
    }

    private func stopMacHeartbeat() {
        macHeartbeat?.cancel()
        macHeartbeat = nil
    }

    private func startLinkWatchdog() {
        linkWatchdog?.cancel()
        linkWatchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, isListening, !isRestartingAfterNetworkChange else { continue }

                if lastPacketReceivedAt == nil {
                    if packetCount == 0 {
                        linkState = .waitingForMac
                        connectionQuality = .unknown
                        refreshStatusMessage()
                        updateConnectionPresentation()
                    }
                    continue
                }

                guard let lastPacket = lastPacketReceivedAt else { continue }
                if ContinuousClock.now - lastPacket > .seconds(4) {
                    if packetCount == 0 {
                        linkState = .waitingForMac
                        connectionQuality = .unknown
                        refreshStatusMessage()
                        updateConnectionPresentation()
                        Task { await self.signalReceiverReadyToMac() }
                    } else {
                        restartAfterNetworkChange()
                    }
                }
            }
        }
    }

    private func stopLinkWatchdog() {
        linkWatchdog?.cancel()
        linkWatchdog = nil
    }

    private func startPlaybackPump() {
        playbackPump?.cancel()
        playbackPump = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1))
                guard let self, isListening else { continue }
                drainReadyPayloads()
            }
        }
    }

    private func stopPlaybackPump() {
        playbackPump?.cancel()
        playbackPump = nil
    }

    private func handleIncomingPacket(_ packet: AudioPacket) {
        lastPacketReceivedAt = ContinuousClock.now
        _ = playbackBuffer.ingest(packet)
        queuedPackets = playbackBuffer.queuedPackets
        packetCount += 1
        packetsSinceUIUpdate += 1
        if packetsSinceUIUpdate >= 20 || playedPacketCount == 0 {
            packetsSinceUIUpdate = 0
            updateConnectionPresentation()
        }
        drainReadyPayloads()
    }

    private func drainReadyPayloads() {
        guard playbackBuffer.queuedPackets > 0 || pendingPlaybackPayload != nil else {
            queuedPackets = playbackBuffer.queuedPackets
            return
        }
        updatePlaybackScheduleLimit()
        guard playbackEngine.canAcceptMoreBuffers else {
            queuedPackets = playbackBuffer.queuedPackets
            return
        }
        do {
            if !playbackEngine.isRunning {
                try playbackEngine.prepare()
                audioOutputIssue = nil
            }
        } catch {
            audioOutputIssue = Self.friendlyAudioError(error)
            queuedPackets = playbackBuffer.queuedPackets
            refreshStatusMessage()
            return
        }
        while playbackEngine.canAcceptMoreBuffers {
            let payload: Data
            if let pendingPlaybackPayload {
                self.pendingPlaybackPayload = nil
                payload = pendingPlaybackPayload
            } else if let next = playbackBuffer.popReadyPayload() {
                payload = next
            } else {
                break
            }

            if playbackEngine.schedule(payload: payload, softened: playbackBuffer.lastPopWasConcealment) {
                playedPacketCount += 1
                linkState = .streaming
                audioOutputIssue = nil
                refreshStatusMessage()
            } else {
                pendingPlaybackPayload = payload
                break
            }
        }
        queuedPackets = playbackBuffer.queuedPackets
        if packetsSinceUIUpdate == 0 {
            updateConnectionPresentation()
        }
    }

    private func updatePlaybackScheduleLimit() {
        let queueDepth = playbackBuffer.queuedPackets
        let scheduled = playbackEngine.scheduledPackets
        let totalDepth = queueDepth + scheduled
        let maxTotal = HushPortConstants.maximumPlaybackLatencyPackets + 6

        if totalDepth > maxTotal {
            playbackEngine.setScheduleAheadLimit(6)
        } else if queueDepth > HushPortConstants.maximumPlaybackLatencyPackets {
            playbackEngine.setScheduleAheadLimit(8)
        } else {
            let headroom = max(8, 18 - queueDepth / 2)
            playbackEngine.setScheduleAheadLimit(headroom)
        }
    }

    private func applyNetworkSnapshot(_ snapshot: IOSNetworkPathMonitor.Snapshot) {
        let signature = snapshot.networkSignature
        let pathChanged = !lastNetworkSignature.isEmpty && signature != lastNetworkSignature
        lastNetworkSignature = signature
        networkUsesWiFi = snapshot.usesWiFi
        if let ip = snapshot.localIPAddress, !ip.isEmpty {
            localIPAddress = ip
        }

        if pathChanged, pairedMac != nil {
            if !snapshot.isSatisfied {
                linkState = .networkUnavailable
                connectionQuality = .poor
                refreshStatusMessage()
            } else {
                restartAfterNetworkChange()
            }
        }
        updateConnectionPresentation()
    }

    private func restartAfterNetworkChange() {
        guard pairedMac != nil, !isRestartingAfterNetworkChange else { return }
        isRestartingAfterNetworkChange = true
        linkState = .reconnecting
        connectionQuality = .unknown
        refreshStatusMessage()
        stopAudio(keepStatus: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            isRestartingAfterNetworkChange = false
            await startAudioAsync(port: UInt16(exactly: port) ?? HushPortConstants.audioPort)
        }
    }

    private func updatePairedMacAddress(_ address: String) {
        guard var mac = pairedMac, mac.networkAddress != address else { return }
        mac.networkAddress = address
        TrustedDeviceStore.save(mac)
        pairedMac = mac
    }

    private func updateConnectionPresentation() {
        connectionQuality = combinedConnectionQuality()
        connectionGuidance = guidanceForCurrentConnection()
    }

    private func combinedConnectionQuality() -> StreamConnectionQuality {
        guard isListening else { return .unknown }
        if packetCount > 0, playedPacketCount == 0 {
            return .poor
        }
        if let lastPacket = lastPacketReceivedAt {
            let age = ContinuousClock.now - lastPacket
            if age > .seconds(5) { return .poor }
            if age > .seconds(2) { return .fair }
            return playedPacketCount > 0 ? .excellent : .fair
        }
        return packetCount > 0 ? .fair : .unknown
    }

    private func guidanceForCurrentConnection() -> String? {
        switch connectionQuality {
        case .poor:
            if packetCount > 0, playedPacketCount == 0 {
                return "Packets arriving but iPhone speakers are not playing. Tap Stop Listening, turn up volume, then Start Listening again."
            }
            if packetCount == 0 || lastPacketReceivedAt == nil {
                return "Not receiving audio from your Mac. Tap Stream Mac audio on the Mac, or reconnect both devices to the same Wi-Fi."
            }
            return "Audio stopped arriving. Reconnecting…"
        case .fair:
            return "Audio connection looks unstable."
        default:
            return nil
        }
    }

    private func prepareAudioPlayback() -> Result<Void, Error> {
        do {
            try playbackEngine.prepare()
            return .success(())
        } catch {
            playbackEngine.reset()
            do {
                try playbackEngine.prepare()
                return .success(())
            } catch let retryError {
                return .failure(retryError)
            }
        }
    }

    func stopAudio(keepStatus: Bool = false) {
        audioTask?.cancel()
        audioTask = nil
        stopPlaybackPump()
        stopMacHeartbeat()
        stopLinkWatchdog()
        receiver?.cancel()
        receiver = nil
        playbackEngine.reset()
        playbackBuffer.reset()
        pendingPlaybackPayload = nil
        packetsSinceUIUpdate = 0
        isListening = false
        queuedPackets = 0
        playedPacketCount = 0
        lastPacketReceivedAt = nil
        audioOutputIssue = nil
        connectionQuality = .unknown
        if !keepStatus {
            status = pairedMac == nil ? "Scan Mac QR code" : "Stopped"
            linkState = .paired
        }
    }

    private static func friendlyAudioError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain {
            switch nsError.code {
            case -50:
                return "Audio output setup failed. Close other audio apps, turn up volume, then tap Stop and Start Listening again."
            case 561015905: // AVAudioSessionErrorCodeCannotStartPlaying
                return "Could not start playback. Tap Stop and Start Listening again."
            default:
                return "Audio output error \(nsError.code). Turn up volume and try Start Listening again."
            }
        }
        return error.localizedDescription
    }

    private func ensureControlChannel() {
        guard controlReceiver == nil else { return }
        do {
            let controlReceiver = try ControlChannelReceiver()
            self.controlReceiver = controlReceiver
            controlTask = Task {
                do {
                    for try await event in controlReceiver.events {
                        guard !Task.isCancelled else { break }
                        handleControl(event)
                    }
                } catch {
                    if !Task.isCancelled {
                        status = error.localizedDescription
                    }
                }
            }
        } catch {
            status = error.localizedDescription
        }
    }

    private func sendPairRequest(to offer: MacPairingOffer) async throws {
        let sender = try ControlChannelSender(host: offer.hostAddress)
        try await sender.prepare()
            try await sender.send(
                ControlMessage(
                    type: .pairRequest,
                    senderID: identity.id,
                    senderName: identity.name,
                    pairingCode: offer.pairingCode,
                    networkAddress: NetworkAddress.localIPv4Address()
                )
            )
        sender.cancel()
    }

    private func waitForPairingResult(for offer: MacPairingOffer) async throws -> TrustedDevice {
        try await withCheckedThrowingContinuation { continuation in
            pairingContinuation = continuation
            Task { @MainActor in
                do {
                    try await sendPairRequest(to: offer)
                } catch {
                    failPairing(with: error)
                }
            }
        }
    }

    private func failPairing(with error: Error) {
        pairingContinuation?.resume(throwing: error)
        pairingContinuation = nil
    }

    private func completePairing(with trusted: TrustedDevice) {
        pairingContinuation?.resume(returning: trusted)
        pairingContinuation = nil
    }

    private func handleControl(_ event: ControlMessageEvent) {
        let message = event.message
        switch message.type {
        case .pairAccept:
            guard pairingContinuation != nil || pendingPairMacID != nil else { return }
            let trusted = TrustedDevice(
                id: message.senderID,
                name: message.senderName,
                networkAddress: message.networkAddress ?? pendingPairMacAddress
            )
            completePairing(with: trusted)
        case .pairReject:
            failPairing(with: PairingClientError.rejected)
            pendingPairMacID = nil
            status = PairingClientError.rejected.localizedDescription
        case .mute:
            playbackEngine.stop()
            status = "Muted by Mac"
        case .unmute:
            do {
                try playbackEngine.ensurePlaying()
                status = "Playing"
                drainReadyPayloads()
            } catch {
                status = Self.friendlyAudioError(error)
            }
        case .ping:
            if let macHost = event.message.networkAddress, !macHost.isEmpty {
                updatePairedMacAddress(macHost)
            } else if let macHost = NetworkEndpointHost.ipv4String(from: event.replyEndpoint) {
                updatePairedMacAddress(macHost)
            }
            if !isListening {
                startAudio()
            } else {
                drainReadyPayloads()
            }
            respond(.pong, to: event.replyEndpoint)
            refreshStatusMessage()
        default:
            break
        }
    }

    private func respond(_ type: ControlMessageType, to endpoint: NWEndpoint) {
        Task {
            do {
                guard let replyEndpoint = ControlReplyEndpoint.resolve(endpoint) else {
                    status = "Could not reply to Mac"
                    return
                }
                let sender = ControlChannelSender(endpoint: replyEndpoint)
                try await sender.prepare()
                try await sender.send(
                    ControlMessage(
                        type: type,
                        senderID: identity.id,
                        senderName: identity.name,
                        networkAddress: NetworkAddress.localIPv4Address()
                    )
                )
                sender.cancel()
            } catch {
                status = "Control response failed"
            }
        }
    }
}

@MainActor
final class IOSNetworkPathMonitor {
    struct Snapshot: Sendable {
        var isSatisfied: Bool
        var usesWiFi: Bool
        var usesCellular: Bool
        var interfaceNames: String
        var localIPAddress: String?

        var networkSignature: String {
            "\(interfaceNames)|\(localIPAddress ?? "none")|\(isSatisfied)"
        }
    }

    private let monitor = NWPathMonitor()
    private(set) var snapshot = Snapshot(
        isSatisfied: true,
        usesWiFi: true,
        usesCellular: false,
        interfaceNames: "",
        localIPAddress: NetworkAddress.localIPv4Address()
    )
    var onUpdate: (@MainActor (Snapshot) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let interfaceNames = path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
            let snapshot = Snapshot(
                isSatisfied: path.status == .satisfied,
                usesWiFi: path.usesInterfaceType(.wifi),
                usesCellular: path.usesInterfaceType(.cellular),
                interfaceNames: interfaceNames,
                localIPAddress: NetworkAddress.localIPv4Address()
            )
            Task { @MainActor in
                guard let self else { return }
                self.snapshot = snapshot
                self.onUpdate?(snapshot)
            }
        }
        monitor.start(queue: DispatchQueue(label: "HushPort.NetworkPath"))
    }

    func stop() {
        monitor.cancel()
    }
}
#endif
