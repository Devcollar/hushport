#if os(iOS)
import AVFAudio
import HushPortCore
import Network
import SwiftUI
import UIKit

enum ReceiverLinkState: Equatable {
    case paired
    case listening
    case waitingForMac
    case streaming
    case reconnecting
    case networkUnavailable
}
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
    private var lastPacketReceivedAt: ContinuousClock.Instant?
    private var isRestartingAfterNetworkChange = false
    private var networkRestartTask: Task<Void, Never>?
    /// User intent. Network/listener restarts must preserve this until the user presses Stop.
    private var listeningIntent = false
    private var pendingPairMacID: UUID?
    private var pendingPairMacAddress: String?
    private var pairingContinuation: CheckedContinuation<TrustedDevice, Error>?
    private var sessionObservers: [NSObjectProtocol] = []
    private var audioOutputIssue: String?
    private var playbackSuspendedForIdle = false

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
        ensureControlChannel(preferWiFi: networkUsesWiFi)
        registerAudioSessionObservers()
        guard pairedMac != nil else {
            status = "Scan Mac QR code"
            linkState = .paired
            return
        }
        linkState = isListening ? .listening : .paired
        if isListening {
            resumePlaybackIfNeeded()
        } else {
            status = "Ready"
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
        if playedPacketCount > 0, !isWaitingForMacAudio {
            status = "Playing from Mac"
            linkState = .streaming
            return
        }
        if packetCount > 0, isWaitingForMacAudio {
            status = "Waiting for audio from \(pairedMac?.name ?? "Mac")"
            linkState = .waitingForMac
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

    private var isWaitingForMacAudio: Bool {
        guard let lastPacket = lastPacketReceivedAt else { return false }
        return packetCount > 0
            && ContinuousClock.now - lastPacket > .seconds(5)
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
            ensureControlChannel(preferWiFi: networkUsesWiFi)
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
                linkState = .paired
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
        listeningIntent = true
        guard !isListening, !isRestartingAfterNetworkChange else { return }
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
            ensureControlChannel(preferWiFi: networkUsesWiFi)
            try await startNetworkListener(port: port)
            startLinkWatchdog()
            refreshStatusMessage()
        } catch {
            status = error.localizedDescription
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
                guard self.isListening else { return }
                self.stopAudio(keepStatus: true)
            }
        }
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
                let packetAge = ContinuousClock.now - lastPacket
                if packetAge > .seconds(5) {
                    if packetCount == 0 {
                        linkState = .waitingForMac
                        connectionQuality = .unknown
                        refreshStatusMessage()
                        updateConnectionPresentation()
                    } else {
                        linkState = .waitingForMac
                        connectionQuality = .unknown
                        refreshStatusMessage()
                        updateConnectionPresentation()
                        suspendPlaybackIfNeeded(packetAge: packetAge)
                    }
                }
            }
        }
    }

    private func suspendPlaybackIfNeeded(packetAge: Duration) {
        guard playedPacketCount > 0,
              !playbackSuspendedForIdle,
              packetAge >= HushPortConstants.playbackSuspendAfterNoPackets else {
            return
        }
        playbackEngine.stop()
        playbackSuspendedForIdle = true
        Self.logPowerEvent("event=playbackSuspended")
    }

    private static func logPowerEvent(_ message: String) {
        #if DEBUG
        print("[POWER][iOS] \(message)")
        #endif
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
        if playbackSuspendedForIdle {
            playbackSuspendedForIdle = false
            Self.logPowerEvent("event=playbackResumed")
        }
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

        if pathChanged {
            if !snapshot.isSatisfied {
                networkRestartTask?.cancel()
                networkRestartTask = nil
                if listeningIntent {
                    linkState = .networkUnavailable
                    connectionQuality = .poor
                    status = "Wi-Fi unavailable — waiting for network"
                }
            } else {
                restartAfterNetworkChange()
            }
        }
        updateConnectionPresentation()
    }

    /// Rebinds both Bonjour listeners after a real NWPath change. The previous
    /// implementation only restarted the audio listener, leaving the control
    /// service attached to the old network. Restarts are coalesced so rapid path
    /// updates do not churn listeners.
    private func restartAfterNetworkChange() {
        networkRestartTask?.cancel()
        let shouldResumeListening = listeningIntent
        isRestartingAfterNetworkChange = true
        if shouldResumeListening {
            linkState = .reconnecting
            connectionQuality = .unknown
            status = "Network changed — reconnecting…"
        }

        if isListening {
            stopAudio(keepStatus: true, preserveIntent: true)
        }
        stopControlChannel()

        networkRestartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }

            self.startControlChannel(preferWiFi: self.networkUsesWiFi)
            if shouldResumeListening, self.listeningIntent, self.pairedMac != nil {
                await self.startAudioAsync(
                    port: UInt16(exactly: self.port) ?? HushPortConstants.audioPort
                )
            }
            guard !Task.isCancelled else { return }
            self.isRestartingAfterNetworkChange = false
            self.networkRestartTask = nil
            if !self.listeningIntent, self.pairedMac != nil {
                self.linkState = .paired
                self.status = "Ready"
            }
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
            if age >= HushPortConstants.playbackSuspendAfterNoPackets {
                return playedPacketCount > 0 ? .fair : .unknown
            }
            if age > .seconds(5) { return .fair }
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
            if isWaitingForMacAudio {
                return nil
            }
            return "Audio stopped arriving unexpectedly."
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

    func stopAudio(keepStatus: Bool = false, preserveIntent: Bool = false) {
        if !preserveIntent {
            listeningIntent = false
            networkRestartTask?.cancel()
            networkRestartTask = nil
            isRestartingAfterNetworkChange = false
        }
        audioTask?.cancel()
        audioTask = nil
        stopPlaybackPump()
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
        playbackSuspendedForIdle = false
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

    private func ensureControlChannel(preferWiFi: Bool = false) {
        guard controlReceiver == nil else { return }
        startControlChannel(preferWiFi: preferWiFi)
    }

    private func stopControlChannel() {
        controlTask?.cancel()
        controlTask = nil
        controlReceiver?.cancel()
        controlReceiver = nil
    }

    private func startControlChannel(preferWiFi: Bool) {
        stopControlChannel()
        do {
            let controlReceiver = try ControlChannelReceiver(
                serviceName: identity.name,
                deviceID: identity.id,
                preferWiFi: preferWiFi
            )
            self.controlReceiver = controlReceiver
            controlTask = Task { @MainActor in
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
            #if DEBUG
            print(
                "[CTRL][iOS] event=pingReceived senderID=\(message.senderID) " +
                "replyEndpoint=\(event.replyEndpoint)"
            )
            #endif
            if let macHost = event.message.networkAddress, !macHost.isEmpty {
                updatePairedMacAddress(macHost)
            } else if let macHost = NetworkEndpointHost.ipv4String(from: event.replyEndpoint) {
                updatePairedMacAddress(macHost)
            }
            if isListening {
                drainReadyPayloads()
            }
            respondToPing(event)
            refreshStatusMessage()
        default:
            break
        }
    }

    private func respondToPing(_ event: ControlMessageEvent) {
        Task { @MainActor in
            do {
                #if DEBUG
                print("[CTRL][iOS] event=pongBegin directFlow=true reply=\(event.replyEndpoint)")
                #endif
                try await event.directReply.send(
                    ControlMessage(
                        type: .pong,
                        senderID: identity.id,
                        senderName: identity.name,
                        networkAddress: NetworkAddress.localIPv4Address()
                    )
                )
                #if DEBUG
                print("[CTRL][iOS] event=pongSendCompleted error=none directFlow=true")
                #endif
            } catch {
                status = "Control response failed"
                #if DEBUG
                print("[CTRL][iOS] event=pongSendCompleted error=\(error.localizedDescription) directFlow=true")
                #endif
            }
        }
    }
}
#endif
