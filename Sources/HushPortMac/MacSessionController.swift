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

    var connectionState: ConnectionState = .searching
    var isMuted = false
    var isSending = false
    var pairedPhone: TrustedDevice?
    var peers: [HushPortPeer] = []
    var selectedPeer: HushPortPeer?
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
    private var discovery: HushPortDiscovery?
    private var controlReceiver: ControlChannelReceiver?
    private var controlTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var keepaliveTask: Task<Void, Never>?
    private var controlSender: ControlChannelSender?
    private var networkMonitor: NWPathMonitor?
    private var currentStreamHost: String?
    private var lastNetworkSignature = ""
    private var reconnectTask: Task<Void, Never>?
    private var pendingPongAddress: String?

    private init() {
        identity = DeviceIdentityStore.load(defaultName: Host.current().localizedName ?? "Mac")
        pairedPhone = TrustedDeviceStore.primary()
        refreshPairingOffer()
        startDiscovery()
        startControlListener()
        startNetworkMonitor()
        autoSelectPairedPeer()
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

    func refreshNetworkInfo() {
        macAddress = NetworkAddress.localIPv4Address() ?? "No local network address"
        if pairedPhone == nil {
            refreshPairingOffer()
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
        selectedPeer = nil
        refreshPairingOffer()
        status = "Scan the QR code with your iPhone"
        connectionState = .searching
    }

    func connectAndStream() {
        reconnectTask?.cancel()
        connectionState = .connecting
        status = "Connecting…"
        if host.isEmpty, let address = pairedPhone?.networkAddress, !address.isEmpty {
            host = address
        }
        reconnectTask = Task { await connectAndStreamAsync(useTestTone: false) }
    }

    func sendTestTone() {
        reconnectTask?.cancel()
        connectionState = .connecting
        status = "Connecting…"
        if host.isEmpty, let address = pairedPhone?.networkAddress, !address.isEmpty {
            host = address
        }
        reconnectTask = Task { await connectAndStreamAsync(useTestTone: true) }
    }

    func connectAndStreamAsync(useTestTone: Bool) async {
        streamTask?.cancel()
        keepaliveTask?.cancel()
        await wakePairedPhone()
        try? await Task.sleep(for: .milliseconds(300))

        guard let target = await waitForStreamTarget() else {
            isSending = false
            connectionState = peers.isEmpty ? .searching : .idle
            status = pairedPhone == nil
                ? "Pair your iPhone or enter its address manually"
                : "Could not reach iPhone. Open HushPort on your iPhone, tap Start Listening, then try again."
            return
        }
        if target.source == .bonjourPeer || target.source == .pairedDeviceAddress {
            host = target.host
        }
        startStreaming(useTestTone: useTestTone, target: target)
    }

    private func wakePairedPhone() async {
        let candidates = streamTargetCandidateHosts(resolvedPeerHosts: await resolveAllPeerHosts())
        guard !candidates.isEmpty else { return }
        for address in candidates.prefix(3) {
            await sendPing(to: address)
        }
    }

    private func sendPing(to address: String) async {
        do {
            let sender = try ControlChannelSender(host: address)
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
            // iPhone may still be waking up.
        }
    }

    private func waitForStreamTarget(maxAttempts: Int = 20) async -> StreamTargetResolver.Target? {
        let port = UInt16(exactly: self.port) ?? HushPortConstants.audioPort
        for attempt in 0..<maxAttempts {
            let resolvedHosts = await resolveAllPeerHosts()
            let candidates = streamTargetCandidateHosts(resolvedPeerHosts: resolvedHosts)

            for candidate in candidates {
                if let verifiedHost = await pingAndWaitForPong(host: candidate, timeout: .milliseconds(700)) {
                    host = verifiedHost
                    return StreamTargetResolver.Target(
                        host: verifiedHost,
                        port: port,
                        source: resolvedHosts.contains(verifiedHost) ? .bonjourPeer : .pairedDeviceAddress
                    )
                }
            }

            if attempt >= maxAttempts - 3, let target = await resolveStreamTarget() {
                return target
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

    private func streamTargetCandidateHosts(resolvedPeerHosts: [String]) -> [String] {
        StreamTargetResolver.candidateHosts(
            resolvedPeerHosts: resolvedPeerHosts,
            pairedDevice: pairedPhone,
            manualHost: host
        )
    }

    private func resolveAllPeerHosts() async -> [String] {
        var hosts: [String] = []
        var seen = Set<String>()

        func add(_ host: String?) {
            guard let host, !host.isEmpty, seen.insert(host).inserted else { return }
            hosts.append(host)
        }

        if let pairedPhone {
            let matchingPeers = peers.filter { peer in
                peer.deviceID == pairedPhone.id
                    || peer.name == pairedPhone.bonjourName
                    || peer.name == pairedPhone.name
            }
            for peer in matchingPeers {
                if let host = await PeerEndpointResolver.resolveHost(for: peer) {
                    add(host)
                    selectedPeer = peer
                    updatePairedPhoneAddress(host, bonjourName: peer.name)
                }
            }
        }

        for peer in peers {
            if let host = await PeerEndpointResolver.resolveHost(for: peer) {
                add(host)
            }
        }

        if let peer = selectedPeer, let host = await PeerEndpointResolver.resolveHost(for: peer) {
            add(host)
            updatePairedPhoneAddress(host, bonjourName: peer.name)
        }

        return hosts
    }

    private func pingAndWaitForPong(host: String, timeout: Duration) async -> String? {
        pendingPongAddress = nil
        await sendPing(to: host)

        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let address = pendingPongAddress {
                pendingPongAddress = nil
                return address
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private func resolvedPhoneAddress(from event: ControlMessageEvent) -> String? {
        if let networkAddress = event.message.networkAddress, !networkAddress.isEmpty {
            return networkAddress
        }
        return NetworkEndpointHost.ipv4String(from: event.replyEndpoint)
    }

    func currentStreamTarget() -> StreamTargetResolver.Target? {
        StreamTargetResolver.resolve(
            peer: selectedPeer,
            pairedDevice: pairedPhone,
            manualHost: host,
            manualPort: UInt16(exactly: port) ?? HushPortConstants.audioPort,
            allowStalePairedAddress: pairedPhone?.networkAddress?.isEmpty == false
        )
    }

    func resolveStreamTarget() async -> StreamTargetResolver.Target? {
        var resolvedPeerHost: String?

        if let pairedPhone {
            let matchingPeers = peers.filter { peer in
                peer.deviceID == pairedPhone.id
                    || peer.name == pairedPhone.bonjourName
                    || peer.name == pairedPhone.name
            }
            for peer in matchingPeers {
                if let host = await PeerEndpointResolver.resolveHost(for: peer) {
                    resolvedPeerHost = host
                    selectedPeer = peer
                    updatePairedPhoneAddress(host, bonjourName: peer.name)
                    break
                }
            }
        }

        if resolvedPeerHost == nil, let peer = selectedPeer {
            resolvedPeerHost = await PeerEndpointResolver.resolveHost(for: peer)
            if let resolvedPeerHost {
                updatePairedPhoneAddress(resolvedPeerHost, bonjourName: peer.name)
            }
        }

        return StreamTargetResolver.resolve(
            peer: selectedPeer,
            resolvedPeerHost: resolvedPeerHost,
            pairedDevice: pairedPhone,
            manualHost: host,
            manualPort: UInt16(exactly: port) ?? HushPortConstants.audioPort,
            allowStalePairedAddress: pairedPhone?.networkAddress?.isEmpty == false
        )
    }

    func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        keepaliveTask?.cancel()
        keepaliveTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        controlSender?.cancel()
        controlSender = nil
        currentStreamHost = nil
        isSending = false
        isMuted = false
        connectionState = peers.isEmpty ? .searching : .idle
        status = statusMessageForIdleState()
    }

    func toggleMute() {
        isMuted.toggle()
        guard let peer = selectedPeer else { return }
        Task {
            do {
                let endpoint = try await PeerEndpointResolver.controlEndpoint(for: peer)
                let sender = ControlChannelSender(endpoint: endpoint)
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
        do {
            let receiver = try ControlChannelReceiver()
            controlReceiver = receiver
            controlTask = Task {
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
                bonjourName: selectedPeer?.name,
                networkAddress: resolvedPhoneAddress(from: event)
            )
            TrustedDeviceStore.save(trusted)
            pairedPhone = trusted
            status = "Paired with \(trusted.name)"
            connectionState = .idle
            respond(.pairAccept, to: event.replyEndpoint)
            autoSelectPairedPeer()
        case .pong:
            if event.message.senderID == pairedPhone?.id {
                phoneReachable = true
            }
            if let address = resolvedPhoneAddress(from: event) {
                updatePairedPhoneAddress(
                    address,
                    bonjourName: selectedPeer?.name
                )
                if event.message.senderID == pairedPhone?.id {
                    pendingPongAddress = address
                }
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
        discovery = HushPortDiscovery { [weak self] peers in
            Task { @MainActor in
                guard let self else { return }
                self.peers = peers
                if let pairedPhone = self.pairedPhone {
                    self.phoneReachable = peers.contains { peer in
                        peer.deviceID == pairedPhone.id
                            || peer.name == pairedPhone.bonjourName
                            || peer.name == pairedPhone.name
                    }
                } else {
                    self.phoneReachable = false
                }
                if let selectedPeer = self.selectedPeer,
                   let refreshed = peers.first(where: { $0.id == selectedPeer.id }) {
                    self.selectedPeer = refreshed
                } else {
                    self.autoSelectPairedPeer()
                }
                await self.refreshDiscoveredPhoneAddress()
                if self.isSending {
                    Task { await self.reconcileActiveStream() }
                } else if !self.isSending {
                    self.connectionState = peers.isEmpty ? .searching : .idle
                    self.status = self.statusMessageForIdleState()
                }
            }
        }
    }

    private func statusMessageForIdleState() -> String {
        if pairedPhone == nil {
            return "Scan the QR code with your iPhone"
        }
        if peers.isEmpty {
            return "iPhone not discovered yet. Open HushPort on your iPhone."
        }
        return "Ready — tap Stream Mac audio"
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
        lastNetworkSignature = signature

        if path.usesInterfaceType(.wifi) {
            networkStatus = path.isExpensive || path.isConstrained ? "Wi-Fi (busy)" : "On Wi-Fi"
        } else if path.status == .satisfied {
            networkStatus = "Network connected"
        } else {
            networkStatus = "No network"
        }

        refreshNetworkInfo()

        guard changed else { return }
        if isSending {
            status = "Network changed — reconnecting…"
            scheduleReconnect()
        } else if pairedPhone != nil {
            status = statusMessageForIdleState()
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let wasMuted = isMuted
            streamTask?.cancel()
            keepaliveTask?.cancel()
            currentStreamHost = nil
            await connectAndStreamAsync(useTestTone: false)
            isMuted = wasMuted
        }
    }

    private func reconcileActiveStream() async {
        guard isSending else { return }
        guard let target = await resolveStreamTarget() else { return }
        if target.host != currentStreamHost {
            status = "Reconnecting to \(target.host)…"
            scheduleReconnect()
        }
    }

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

    private func applyDiscoveredPhoneAddress(_ address: String) {
        guard !address.isEmpty else { return }
        let previousPaired = pairedPhone?.networkAddress
        if host.isEmpty || host == previousPaired {
            host = address
        }
        updatePairedPhoneAddress(address, bonjourName: selectedPeer?.name)
    }

    private func refreshDiscoveredPhoneAddress() async {
        guard pairedPhone != nil else { return }
        let resolvedHosts = await resolveAllPeerHosts()
        if let latest = resolvedHosts.first {
            applyDiscoveredPhoneAddress(latest)
        }
    }

    private func autoSelectPairedPeer() {
        guard let pairedPhone else {
            selectedPeer = peers.first
            return
        }
        if let address = pairedPhone.networkAddress, !address.isEmpty, host.isEmpty {
            host = address
        }
        if let match = peers.first(where: { $0.deviceID == pairedPhone.id || $0.name == pairedPhone.bonjourName }) {
            selectedPeer = match
        } else {
            selectedPeer = peers.first
        }
    }

    private func startStreaming(useTestTone: Bool, target: StreamTargetResolver.Target) {
        streamTask?.cancel()
        keepaliveTask?.cancel()
        controlSender?.cancel()
        controlSender = nil
        isSending = true
        connectionState = .connecting
        packetsSent = 0
        currentStreamHost = target.host
        status = "Connecting to \(target.host)…"
        streamTask = Task {
            do {
                let sender = try UDPAudioSender(host: target.host, port: target.port)
                defer { sender.cancel() }
                try await sender.prepare()
                await notifyReceiver(at: target.host)
                var sequence: UInt32 = 0
                let clock = ContinuousClock()
                var nextDeadline = clock.now
                var phase = 0.0
                var silentCaptureFrames = 0
                var lastCapturedPayload: Data?
                let capture = useTestTone ? nil : try? SharedAudioCapture()
                if !useTestTone, capture == nil {
                    status = "HushPort Audio is not running. Select HushPort in System Settings → Sound → Output."
                }
                connectionState = .streaming
                status = useTestTone
                    ? "Sending test tone to \(target.host)"
                    : "Streaming Mac audio to \(target.host)"
                startKeepalive(to: target.host)
                let packetDuration = AudioStreamFormat.prototype.packetDuration
                while !Task.isCancelled {
                    if clock.now < nextDeadline {
                        try await clock.sleep(until: nextDeadline, tolerance: .microseconds(250))
                    }
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
                            status = "Connected, but no audio from HushPort output. Select HushPort in System Settings → Sound → Output."
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
                    packetsSent = Int(sequence)
                    let advancedDeadline = nextDeadline.advanced(by: packetDuration)
                    if clock.now > advancedDeadline {
                        nextDeadline = clock.now.advanced(by: packetDuration)
                    } else {
                        nextDeadline = advancedDeadline
                    }
                }
            } catch is CancellationError {
            } catch {
                status = error.localizedDescription
                connectionState = .error(error.localizedDescription)
            }
            keepaliveTask?.cancel()
            keepaliveTask = nil
            isSending = false
            currentStreamHost = nil
            if connectionState == .streaming { connectionState = .idle }
        }
    }

    private func startKeepalive(to host: String) {
        keepaliveTask?.cancel()
        keepaliveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await notifyReceiver(at: host)
            }
        }
    }

    private func notifyReceiver(at host: String) async {
        do {
            let sender = try ControlChannelSender(host: host)
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
            status = "Streaming to \(host), but could not wake iPhone listener"
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
