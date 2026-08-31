#if os(macOS)
import Foundation
import HushPortCore
import Network
import SwiftUI

@MainActor @Observable
final class MacSessionController {
    static let shared = MacSessionController()

    enum ConnectionState: Equatable {
        case idle
        case searching
        case connecting
        case streaming
        case error(String)
    }

    private struct StreamSessionBinding: Equatable {
        let generation: UInt64
        let deviceID: UUID
        let routeRevision: UInt64
        let audioEndpoint: NWEndpoint
        let controlEndpoint: NWEndpoint
    }

    var connectionState: ConnectionState = .searching
    var isMuted = false
    var isSending = false
    var pairedPhone: TrustedDevice?
    var discoveredReceivers: [DiscoveredReceiver] = []
    var macPairingCode = PairingCodeGenerator.makeCode()
    var pairingQRImage: Image?
    var status = "Searching for iPhone…"
    var macAddress = NetworkAddress.localIPv4Address() ?? "No local network address"
    var host = ""
    var port = Int(HushPortConstants.audioPort)
    var packetsSent = 0
    var phoneReachable = false
    var networkStatus = "On Wi-Fi"

    private let identity: DeviceIdentity
    private var discovery: ReceiverDiscovery?
    private var receiverRegistry: ReceiverRegistry?
    private var controlReceiver: ControlChannelReceiver?
    private var controlTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?
    private var activeStreamRoute: StreamRoute?
    private var activeSessionBinding: StreamSessionBinding?
    private var lastNetworkSignature = ""
    private var reconnectTask: Task<Void, Never>?
    private var streamGeneration: UInt64 = 0
    private var lastMacIPAddress = ""
    private var lastScheduledReconnectRevision: UInt64?
    private var bonjourBrowseFailed = false

    private init() {
        identity = DeviceIdentityStore.load(defaultName: Host.current().localizedName ?? "Mac")
        pairedPhone = TrustedDeviceStore.primary()
        refreshPairingOffer()
        startDiscovery()
        startControlListener()
        startNetworkMonitor()
        refreshPairedReceiverState()
    }

    var menuBarIcon: String {
        switch connectionState {
        case .streaming: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .connecting, .searching: "dot.radiowaves.left.and.right"
        case .error: "exclamationmark.triangle.fill"
        case .idle: "speaker.fill"
        }
    }

    var pairedPhoneName: String {
        pairedPhone?.name ?? "Not paired"
    }

    var pairedReceiver: DiscoveredReceiver? {
        guard let pairedPhone else { return nil }
        return receiverRegistry?.receiver(for: pairedPhone.id)
    }

    var canStartStreaming: Bool {
        if !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return pairedPhone != nil
        }
        return pairedReceiver?.isReady == true
    }

    func refreshNetworkInfo() {
        macAddress = NetworkAddress.localIPv4Address() ?? "No local network address"
        if pairedPhone == nil {
            refreshPairingOffer()
        } else {
            refreshPairedReceiverState()
        }
    }

    func refreshPairingOffer() {
        macPairingCode = PairingCodeGenerator.makeCode()
        let host = NetworkAddress.localIPv4Address() ?? "127.0.0.1"
        let offer = MacPairingOffer(
            deviceID: identity.id,
            deviceName: identity.name,
            pairingCode: macPairingCode,
            hostAddress: host
        )
        pairingQRImage = QRCodeImage.makeImage(from: PairingPayload.makeURL(offer: offer))
        if pairedPhone == nil {
            status = "Scan the QR code with your iPhone"
        }
    }

    func forgetPairing() {
        disconnect()
        TrustedDeviceStore.clear()
        pairedPhone = nil
        phoneReachable = false
        refreshPairingOffer()
        status = "Scan the QR code with your iPhone"
        connectionState = .searching
    }

    func connectAndStream() {
        reconnectTask?.cancel()
        connectionState = .connecting
        status = "Connecting…"
        reconnectTask = Task { await connectAndStreamAsync(useTestTone: false) }
    }

    func sendTestTone() {
        reconnectTask?.cancel()
        connectionState = .connecting
        status = "Connecting…"
        reconnectTask = Task { await connectAndStreamAsync(useTestTone: true) }
    }

    func connectAndStreamAsync(useTestTone: Bool) async {
        guard !Task.isCancelled else { return }
        streamTask?.cancel()
        keepaliveTask?.cancel()

        guard let route = await waitForStreamRoute() else {
            guard !Task.isCancelled else { return }
            isSending = false
            connectionState = pairedReceiver == nil ? .searching : .idle
            status = pairedPhone == nil
                ? "Pair your iPhone or enter its address manually"
                : manualStreamRoute() != nil
                    ? "Could not reach iPhone at the manual address."
                    : bonjourBrowseFailed
                        ? "Local Network access required — enable HushPort in System Settings → Privacy & Security → Local Network"
                        : "Looking for your paired iPhone on this network. Open HushPort on iPhone and tap Start Listening."
            return
        }

        guard !Task.isCancelled else { return }
        startStreaming(useTestTone: useTestTone, route: route)
    }

    private func waitForStreamRoute(maxAttempts: Int = 20) async -> StreamRoute? {
        for attempt in 0..<maxAttempts {
            guard !Task.isCancelled else { return nil }

            if let route = await automaticStreamRouteIfReady() {
                return route
            }
            if let manual = manualStreamRoute(), await verifyManualRoute(manual) {
                return manual
            }

            if attempt == 0 {
                status = "Looking for iPhone…"
            }
            if attempt.isMultiple(of: 4) {
                await wakePairedPhone()
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    private func automaticStreamRouteIfReady() async -> StreamRoute? {
        guard let pairedPhone,
              let receiver = receiverRegistry?.receiver(for: pairedPhone.id),
              let audioEndpoint = receiver.audioEndpoint,
              let controlEndpoint = receiver.controlEndpoint else {
            return nil
        }

        guard await verifyReceiver(controlEndpoint: controlEndpoint, expectedDeviceID: pairedPhone.id) else {
            return nil
        }

        return StreamRoute(
            deviceID: pairedPhone.id,
            audioEndpoint: audioEndpoint,
            controlEndpoint: controlEndpoint,
            routeRevision: receiver.routeRevision,
            source: .bonjour
        )
    }

    private func manualStreamRoute() -> StreamRoute? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty,
              let audioPort = NWEndpoint.Port(rawValue: UInt16(exactly: port) ?? HushPortConstants.audioPort),
              let controlPort = NWEndpoint.Port(rawValue: HushPortConstants.controlPort),
              let deviceID = pairedPhone?.id else {
            return nil
        }
        return StreamRoute(
            deviceID: deviceID,
            audioEndpoint: .hostPort(host: NWEndpoint.Host(trimmedHost), port: audioPort),
            controlEndpoint: .hostPort(host: NWEndpoint.Host(trimmedHost), port: controlPort),
            routeRevision: 0,
            source: .manualHost
        )
    }

    private func verifyManualRoute(_ route: StreamRoute) async -> Bool {
        await verifyReceiver(controlEndpoint: route.controlEndpoint, expectedDeviceID: route.deviceID)
    }

    private func wakePairedPhone() async {
        guard let pairedPhone else { return }
        if let controlEndpoint = receiverRegistry?.receiver(for: pairedPhone.id)?.controlEndpoint {
            await sendPing(to: controlEndpoint, expectedDeviceID: pairedPhone.id)
            return
        }
        if let manual = manualStreamRoute() {
            await sendPing(to: manual.controlEndpoint, expectedDeviceID: manual.deviceID)
        }
    }

    private func sendPing(to controlEndpoint: NWEndpoint, expectedDeviceID: UUID) async {
        do {
            #if DEBUG
            print("[CTRL][Mac] event=pingBegin device=\(expectedDeviceID) endpoint=\(controlEndpoint)")
            #endif
            let sender = ControlChannelSender(endpoint: controlEndpoint, debugPlatform: "Mac")
            try await sender.prepare()
            try await sendPing(using: sender)
            sender.cancel()
            #if DEBUG
            print("[CTRL][Mac] event=pingSendCompleted error=none")
            #endif
        } catch {
            #if DEBUG
            print("[CTRL][Mac] event=pingSendCompleted error=\(error.localizedDescription)")
            #endif
        }
    }

    private func sendPing(using sender: ControlChannelSender) async throws {
        try await sender.send(
            ControlMessage(
                type: .ping,
                senderID: identity.id,
                senderName: identity.name,
                networkAddress: NetworkAddress.localIPv4Address()
            )
        )
    }

    private func verifyReceiver(controlEndpoint: NWEndpoint, expectedDeviceID: UUID) async -> Bool {
        do {
            #if DEBUG
            print("[CTRL][Mac] event=pingBegin device=\(expectedDeviceID) endpoint=\(controlEndpoint)")
            #endif
            let sender = ControlChannelSender(endpoint: controlEndpoint, debugPlatform: "Mac")
            defer { sender.cancel() }
            try await sender.prepare()
            try await sendPing(using: sender)
            guard let data = await sender.receive(timeout: .seconds(2)),
                  let message = try? ControlMessage(decoding: data),
                  message.type == .pong,
                  message.senderID == expectedDeviceID else {
                #if DEBUG
                print("[CTRL][Mac] event=pongReceived inline matched=false")
                #endif
                return false
            }
            #if DEBUG
            print("[CTRL][Mac] event=pongReceived inline senderID=\(message.senderID) matched=true")
            #endif
            phoneReachable = true
            if let address = message.networkAddress, !address.isEmpty {
                updatePairedPhoneAddress(address, bonjourName: pairedReceiver?.displayName)
            }
            return true
        } catch {
            #if DEBUG
            print("[CTRL][Mac] event=pingSendCompleted error=\(error.localizedDescription)")
            #endif
            return false
        }
    }

    private func resolvedPhoneAddress(from event: ControlMessageEvent) -> String? {
        if let networkAddress = event.message.networkAddress, !networkAddress.isEmpty {
            return networkAddress
        }
        return NetworkEndpointHost.ipv4String(from: event.replyEndpoint)
    }

    func disconnect() {
        streamGeneration &+= 1
        reconnectTask?.cancel()
        reconnectTask = nil
        streamTask?.cancel()
        streamTask = nil
        keepaliveTask?.cancel()
        keepaliveTask = nil
        activeStreamRoute = nil
        activeSessionBinding = nil
        lastScheduledReconnectRevision = nil
        isSending = false
        isMuted = false
        connectionState = pairedReceiver == nil ? .searching : .idle
        status = statusMessageForIdleState()
    }

    func toggleMute() {
        isMuted.toggle()
        guard let controlEndpoint = activeStreamRoute?.controlEndpoint
            ?? pairedReceiver?.controlEndpoint else { return }
        Task {
            do {
                let sender = ControlChannelSender(endpoint: controlEndpoint)
                try await sender.prepare()
                try await sender.send(
                    ControlMessage(
                        type: isMuted ? .mute : .unmute,
                        senderID: identity.id,
                        senderName: identity.name,
                        muted: isMuted
                    )
                )
                sender.cancel()
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func startControlListener() {
        controlTask?.cancel()
        controlReceiver?.cancel()
        do {
            let receiver = try ControlChannelReceiver()
            controlReceiver = receiver
            controlTask = Task { @MainActor in
            do {
                for try await event in receiver.events {
                    guard !Task.isCancelled else { break }
                    handleControl(event)
                }
            } catch {
                status = error.localizedDescription
            }
        }
        } catch {
            status = error.localizedDescription
        }
    }

    private func handleControl(_ event: ControlMessageEvent) {
        switch event.message.type {
        case .pairRequest:
            guard pairedPhone == nil,
                  let code = event.message.pairingCode,
                  code == macPairingCode else {
                respond(.pairReject, to: event.replyEndpoint)
                return
            }
            let trusted = TrustedDevice(
                id: event.message.senderID,
                name: event.message.senderName,
                bonjourName: pairedReceiver?.displayName,
                networkAddress: resolvedPhoneAddress(from: event)
            )
            TrustedDeviceStore.save(trusted)
            pairedPhone = trusted
            status = "Paired with \(trusted.name)"
            connectionState = .idle
            respond(.pairAccept, to: event.replyEndpoint)
            refreshPairedReceiverState()
        case .pong:
            let matchedPairedPhone = event.message.senderID == pairedPhone?.id
            #if DEBUG
            print(
                "[CTRL][Mac] event=pongReceived senderID=\(event.message.senderID) " +
                "expectedID=\(pairedPhone?.id.uuidString ?? "nil") matched=\(matchedPairedPhone)"
            )
            #endif
            guard matchedPairedPhone else { return }
            phoneReachable = true
            if let address = resolvedPhoneAddress(from: event) {
                updatePairedPhoneAddress(address, bonjourName: pairedReceiver?.displayName)
            }
            if isSending {
                Task { await reconcileActiveStream() }
            }
        case .unpair:
            guard let pairedPhone, event.message.senderID == pairedPhone.id else { return }
            forgetPairing()
        default:
            break
        }
    }

    private func respond(_ type: ControlMessageType, to endpoint: NWEndpoint) {
        Task {
            do {
                guard let replyEndpoint = ControlReplyEndpoint.resolve(endpoint) else {
                    status = "Pairing response failed"
                    return
                }
                let sender = ControlChannelSender(endpoint: replyEndpoint)
                try await sender.prepare()
                try await sender.send(
                    ControlMessage(
                        type: type,
                        senderID: identity.id,
                        senderName: identity.name
                    )
                )
                sender.cancel()
            } catch {
                status = "Pairing response failed"
            }
        }
    }

    private func startDiscovery() {
        discovery = ReceiverDiscovery(
            onChange: { [weak self] receivers in
                Task { @MainActor in
                    guard let self else { return }
                    self.discoveredReceivers = receivers
                    if !receivers.isEmpty {
                        self.bonjourBrowseFailed = false
                    }
                    self.refreshPairedReceiverState()
                    if self.isSending {
                        self.handleRouteChangeWhileStreaming()
                    } else {
                        self.connectionState = self.pairedReceiver == nil ? .searching : .idle
                        self.status = self.statusMessageForIdleState()
                    }
                }
            },
            onBrowseIssue: { [weak self] issue in
                Task { @MainActor in
                    guard let self else { return }
                    let authFailure = issue.localizedCaseInsensitiveContains("NoAuth")
                        || issue.contains("-65555")
                    if authFailure {
                        self.bonjourBrowseFailed = true
                        self.status = self.statusMessageForIdleState()
                    }
                }
            }
        )
        receiverRegistry = discovery?.registry
    }

    private func restartDiscovery() {
        discovery?.cancel()
        discovery = nil
        receiverRegistry = nil
        discoveredReceivers = []
        bonjourBrowseFailed = false
        startDiscovery()
    }

    private func refreshPairedReceiverState() {
        guard let pairedPhone else {
            phoneReachable = false
            return
        }
        if let receiver = receiverRegistry?.receiver(for: pairedPhone.id), receiver.isReady {
            phoneReachable = true
            return
        }
        phoneReachable = false
    }

    private func statusMessageForIdleState() -> String {
        if pairedPhone == nil {
            return "Scan the QR code with your iPhone"
        }
        guard let receiver = pairedReceiver else {
            if bonjourBrowseFailed {
                return "Local Network access required — enable HushPort in System Settings → Privacy & Security → Local Network"
            }
            return "iPhone not discovered yet. Open HushPort on your iPhone."
        }
        switch receiver.readiness {
        case .ready:
            return "Ready — tap Stream Mac audio"
        case .audioOnly:
            return "iPhone found — waiting for control service…"
        case .controlOnly:
            return "iPhone found — waiting for audio service…"
        }
    }

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handleNetworkPathChange(path)
            }
        }
        monitor.start(queue: DispatchQueue(label: "HushPort.MacNetwork"))
        networkMonitor = monitor
    }

    private func handleNetworkPathChange(_ path: NWPath) {
        let interfaceNames = path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
        let localIP = NetworkAddress.localIPv4Address() ?? "none"
        let signature = "\(interfaceNames)|\(localIP)"
        let changed = signature != lastNetworkSignature
        let ipChanged = localIP != lastMacIPAddress
        lastNetworkSignature = signature
        lastMacIPAddress = localIP

        if path.usesInterfaceType(.wifi) {
            networkStatus = path.isExpensive || path.isConstrained ? "Wi-Fi (busy)" : "On Wi-Fi"
        } else if path.status == .satisfied {
            networkStatus = "Network connected"
        } else {
            networkStatus = "No network"
        }

        refreshNetworkInfo()

        guard changed else { return }
        if ipChanged, pairedPhone != nil {
            restartDiscovery()
        }
        if isSending {
            status = "Network changed — reconnecting…"
            scheduleReconnect()
        } else if pairedPhone != nil {
            status = statusMessageForIdleState()
        }
    }

    private func handleRouteChangeWhileStreaming() {
        guard isSending,
              let pairedPhone,
              let binding = activeSessionBinding,
              let receiver = receiverRegistry?.receiver(for: pairedPhone.id),
              receiver.routeRevision != binding.routeRevision else {
            return
        }
        #if DEBUG
        print("[HushPort] route replacement device=\(pairedPhone.id) old=\(binding.routeRevision) new=\(receiver.routeRevision)")
        #endif
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard let pairedPhone,
              let receiver = receiverRegistry?.receiver(for: pairedPhone.id),
              receiver.isReady else { return }
        if lastScheduledReconnectRevision == receiver.routeRevision {
            return
        }
        lastScheduledReconnectRevision = receiver.routeRevision

        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let wasMuted = isMuted
            streamTask?.cancel()
            keepaliveTask?.cancel()
            activeStreamRoute = nil
            activeSessionBinding = nil
            await connectAndStreamAsync(useTestTone: false)
            guard !Task.isCancelled else { return }
            isMuted = wasMuted
        }
    }

    private func reconcileActiveStream() async {
        guard isSending,
              let binding = activeSessionBinding,
              let receiver = receiverRegistry?.receiver(for: binding.deviceID),
              receiver.isReady,
              let audioEndpoint = receiver.audioEndpoint,
              let controlEndpoint = receiver.controlEndpoint else { return }

        let currentRoute = StreamRoute(
            deviceID: binding.deviceID,
            audioEndpoint: audioEndpoint,
            controlEndpoint: controlEndpoint,
            routeRevision: receiver.routeRevision,
            source: .bonjour
        )

        if currentRoute.routeRevision != binding.routeRevision
            || currentRoute.audioEndpoint != binding.audioEndpoint
            || currentRoute.controlEndpoint != binding.controlEndpoint {
            scheduleReconnect()
        }
    }

    /// Persists last-observed address for diagnostics/display only.
    /// Automatic routing must come from ReceiverRegistry Bonjour endpoints.
    private func updatePairedPhoneAddress(_ address: String?, bonjourName: String?) {
        guard let pairedPhone, let address, !address.isEmpty else { return }
        if pairedPhone.networkAddress == address,
           bonjourName == nil || pairedPhone.bonjourName == bonjourName {
            return
        }
        var updated = pairedPhone
        updated.networkAddress = address
        if let bonjourName {
            updated.bonjourName = bonjourName
        }
        TrustedDeviceStore.save(updated)
        self.pairedPhone = updated
    }

    private func startStreaming(useTestTone: Bool, route: StreamRoute) {
        guard !Task.isCancelled else { return }
        streamTask?.cancel()
        keepaliveTask?.cancel()
        streamGeneration &+= 1
        let generation = streamGeneration
        let binding = StreamSessionBinding(
            generation: generation,
            deviceID: route.deviceID,
            routeRevision: route.routeRevision,
            audioEndpoint: route.audioEndpoint,
            controlEndpoint: route.controlEndpoint
        )
        activeSessionBinding = binding
        activeStreamRoute = route
        lastScheduledReconnectRevision = nil
        #if DEBUG
        print("[HushPort] stream start generation=\(generation) revision=\(route.routeRevision) audio=\(route.audioEndpoint)")
        #endif
        isSending = true
        connectionState = .connecting
        packetsSent = 0
        status = "Connecting…"
        streamTask = Task {
            var ownedKeepalive: Task<Void, Never>?
            do {
                let sender = UDPAudioSender(endpoint: route.audioEndpoint)
                defer { sender.cancel() }
                try await sender.prepare()
                await notifyReceiver(controlEndpoint: route.controlEndpoint, binding: binding)
                var sequence: UInt32 = 0
                let clock = ContinuousClock()
                var nextDeadline = clock.now
                var phase = 0.0
                var silentCaptureFrames = 0
                var lastCapturedPayload: Data?
                let capture = useTestTone ? nil : try? SharedAudioCapture()
                if !useTestTone, capture == nil {
                    setStreamPresentationState(
                        binding: binding,
                        status: "HushPort Audio is not running. Select HushPort in System Settings → Sound → Output."
                    )
                }
                setStreamPresentationState(
                    binding: binding,
                    connectionState: .streaming,
                    status: useTestTone ? "Sending test tone" : "Streaming Mac audio"
                )
                ownedKeepalive = startKeepalive(controlEndpoint: route.controlEndpoint, binding: binding)
                let packetDuration = AudioStreamFormat.prototype.packetDuration
                while !Task.isCancelled, isCurrentStreamBinding(binding) {
                    if clock.now < nextDeadline {
                        try await clock.sleep(until: nextDeadline, tolerance: .microseconds(250))
                    }
                    guard isCurrentStreamBinding(binding) else { break }
                    let payload: Data
                    if isMuted {
                        payload = Self.silencePayload()
                    } else if useTestTone {
                        payload = Self.tonePayload(phase: &phase)
                    } else if let capture, let captured = capture.readPayload() {
                        silentCaptureFrames = 0
                        lastCapturedPayload = captured
                        payload = captured
                    } else if let lastCapturedPayload {
                        payload = lastCapturedPayload
                    } else {
                        silentCaptureFrames += 1
                        if silentCaptureFrames == 48 {
                            setStreamPresentationState(
                                binding: binding,
                                status: "Connected, but no audio from HushPort output. Select HushPort in System Settings → Sound → Output."
                            )
                        }
                        payload = Self.silencePayload()
                    }
                    let packet = AudioPacket(
                        streamID: HushPortConstants.defaultStreamID,
                        sequenceNumber: sequence,
                        captureTimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                        payload: payload
                    )
                    try sender.sendRealtime(packet)
                    sequence &+= 1
                    if isCurrentStreamBinding(binding) {
                        packetsSent = Int(sequence)
                    }
                    let advancedDeadline = nextDeadline.advanced(by: packetDuration)
                    if clock.now > advancedDeadline {
                        nextDeadline = clock.now.advanced(by: packetDuration)
                    } else {
                        nextDeadline = advancedDeadline
                    }
                }
            } catch is CancellationError {
            } catch {
                setStreamPresentationState(
                    binding: binding,
                    connectionState: .error(error.localizedDescription),
                    status: error.localizedDescription
                )
            }
            finishStreamSession(binding: binding, ownedKeepalive: ownedKeepalive)
        }
    }

    private func isCurrentStreamBinding(_ binding: StreamSessionBinding) -> Bool {
        binding.generation == streamGeneration
            && activeSessionBinding == binding
    }

    private func setStreamPresentationState(
        binding: StreamSessionBinding,
        connectionState: ConnectionState? = nil,
        status: String? = nil
    ) {
        guard isCurrentStreamBinding(binding) else { return }
        if let connectionState {
            self.connectionState = connectionState
        }
        if let status {
            self.status = status
        }
    }

    private func finishStreamSession(
        binding: StreamSessionBinding,
        ownedKeepalive: Task<Void, Never>?
    ) {
        guard isCurrentStreamBinding(binding) else {
            #if DEBUG
            print("[HushPort] stale stream generation \(binding.generation) cleanup ignored; current=\(streamGeneration)")
            #endif
            return
        }
        ownedKeepalive?.cancel()
        keepaliveTask = nil
        streamTask = nil
        isSending = false
        activeStreamRoute = nil
        activeSessionBinding = nil
        if connectionState == .streaming {
            connectionState = .idle
        }
    }

    @discardableResult
    private func startKeepalive(
        controlEndpoint: NWEndpoint,
        binding: StreamSessionBinding
    ) -> Task<Void, Never> {
        let keepalive = Task {
            while !Task.isCancelled, isCurrentStreamBinding(binding) {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, isCurrentStreamBinding(binding) else { break }
                await notifyReceiver(controlEndpoint: controlEndpoint, binding: binding)
            }
        }
        keepaliveTask = keepalive
        return keepalive
    }

    private func notifyReceiver(
        controlEndpoint: NWEndpoint,
        binding: StreamSessionBinding
    ) async {
        guard isCurrentStreamBinding(binding) else { return }
        do {
            let sender = ControlChannelSender(endpoint: controlEndpoint)
            try await sender.prepare()
            try await sender.send(
                ControlMessage(
                    type: .ping,
                    senderID: identity.id,
                    senderName: identity.name,
                    networkAddress: NetworkAddress.localIPv4Address()
                )
            )
            sender.cancel()
        } catch {
            setStreamPresentationState(
                binding: binding,
                status: "Streaming, but could not wake iPhone listener"
            )
        }
    }

    private static func silencePayload() -> Data {
        Data(count: AudioStreamFormat.prototype.payloadByteCount)
    }

    private static func tonePayload(phase: inout Double) -> Data {
        let format = AudioStreamFormat.prototype
        var samples = [Int16]()
        samples.reserveCapacity(Int(format.framesPerPacket) * Int(format.channelCount))
        let increment = 2 * Double.pi * 440 / Double(format.sampleRate)
        for _ in 0..<format.framesPerPacket {
            let sample = Int16(sin(phase) * Double(Int16.max) * 0.15)
            phase = (phase + increment).truncatingRemainder(dividingBy: 2 * .pi)
            samples.append(sample)
            samples.append(sample)
        }
        return samples.withUnsafeBytes { Data($0) }
    }
}

enum PairingError: LocalizedError {
    case timeout
    case rejected

    var errorDescription: String? {
        switch self {
        case .timeout: "Pairing timed out. Check the code and try again."
        case .rejected: "Pairing was rejected by the iPhone."
        }
    }
}
#endif
