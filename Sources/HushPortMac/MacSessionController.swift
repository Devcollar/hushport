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
    private var streamGeneration: UInt64 = 0
    private var addressRefreshTask: Task<Void, Never>?
    private var lastMacIPAddress = ""

    private init() {
        identity = DeviceIdentityStore.load(defaultName: Host.current().localizedName ?? "Mac")
        pairedPhone = TrustedDeviceStore.primary()
        clearStalePairedAddressIfNeeded()
        refreshPairingOffer()
        startDiscovery()
        startControlListener()
        startNetworkMonitor()
        startAddressRefreshLoop()
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
        clearStalePairedAddressIfNeeded()
        if pairedPhone != nil {
            Task { await refreshDiscoveredPhoneAddress() }
        }
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
        clearStalePairedAddressIfNeeded()
        seedHostFromPairingIfNeeded()
        reconnectTask = Task { await connectAndStreamAsync(useTestTone: false) }
    }

    func sendTestTone() {
        reconnectTask?.cancel()
        connectionState = .connecting
        status = "Connecting…"
        clearStalePairedAddressIfNeeded()
        seedHostFromPairingIfNeeded()
        reconnectTask = Task { await connectAndStreamAsync(useTestTone: true) }
    }

    func connectAndStreamAsync(useTestTone: Bool) async {
        guard !Task.isCancelled else { return }
        streamTask?.cancel()
        keepaliveTask?.cancel()
        await wakePairedPhone()
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        guard let target = await waitForStreamTarget() else {
            guard !Task.isCancelled else { return }
            isSending = false
            connectionState = peers.isEmpty ? .searching : .idle
            status = pairedPhone == nil
                ? "Pair your iPhone or enter its address manually"
                : "Could not reach iPhone. Open HushPort on your iPhone, tap Start Listening, then try again."
            return
        }
        guard !Task.isCancelled else { return }
        if target.source == .bonjourPeer || target.source == .pairedDeviceAddress {
            host = target.host
        }
        startStreaming(useTestTone: useTestTone, target: target)
    }

    private func wakePairedPhone() async {
        for peer in matchingPeersForPairedPhone().prefix(3) {
            await sendPing(to: peer)
        }
        let candidates = streamTargetCandidateHosts(resolvedPeerHosts: await resolveAllPeerHosts())
        for address in candidates.prefix(3) {
            await sendPing(to: address)
        }
    }

    private func sendPing(to address: String) async {
        do {
            let sender = try ControlChannelSender(host: address)
            try await sender.prepare()
            try await sendPing(using: sender)
            sender.cancel()
        } catch {
            // iPhone may still be waking up.
        }
    }

    private func sendPing(to peer: HushPortPeer) async {
        if let host = await PeerEndpointResolver.resolveHost(for: peer) {
            await sendPing(to: host)
            return
        }
        do {
            let endpoint = try await PeerEndpointResolver.controlEndpoint(for: peer)
            let sender = ControlChannelSender(endpoint: endpoint)
            try await sender.prepare()
            try await sendPing(using: sender)
            sender.cancel()
        } catch {
            // Bonjour resolution may still be in progress.
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

    private func waitForStreamTarget(maxAttempts: Int = 20) async -> StreamTargetResolver.Target? {
        let port = UInt16(exactly: self.port) ?? HushPortConstants.audioPort
        for attempt in 0..<maxAttempts {
            guard !Task.isCancelled else { return nil }
            let resolvedHosts = await resolveAllPeerHosts()
            let candidates = streamTargetCandidateHosts(resolvedPeerHosts: resolvedHosts)

            for peer in matchingPeersForPairedPhone() {
                if let verifiedHost = await pingAndWaitForPong(peer: peer, timeout: .milliseconds(1_200)) {
                    host = verifiedHost
                    selectedPeer = peer
                    updatePairedPhoneAddress(verifiedHost, bonjourName: peer.name)
                    return StreamTargetResolver.Target(
                        host: verifiedHost,
                        port: port,
                        source: .bonjourPeer
                    )
                }
            }

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
        var seen = Set<String>()
        var hosts: [String] = []

        func add(_ value: String?) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
            hosts.append(trimmed)
        }

        for resolvedHost in resolvedPeerHosts {
            add(resolvedHost)
        }

        let storedAddress = pairedPhone?.networkAddress
        let trimmedManualHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let manualOverride = !trimmedManualHost.isEmpty
            && trimmedManualHost != storedAddress
            && !resolvedPeerHosts.contains(trimmedManualHost)

        if resolvedPeerHosts.isEmpty {
            if let stored = pairedPhone?.networkAddress,
               isReachableStoredAddress(stored) {
                add(stored)
            }
            add(trimmedManualHost)
        } else if manualOverride {
            add(trimmedManualHost)
        }

        return hosts
    }

    private func resolveAllPeerHosts() async -> [String] {
        var hosts: [String] = []
        var seen = Set<String>()

        func add(_ host: String?) {
            guard let host, !host.isEmpty, seen.insert(host).inserted else { return }
            hosts.append(host)
        }

        let pairedMatches = matchingPeersForPairedPhone()
        for peer in pairedMatches {
            if let host = await PeerEndpointResolver.resolveHost(for: peer) {
                add(host)
                selectedPeer = peer
                updatePairedPhoneAddress(host, bonjourName: peer.name)
            }
        }

        for peer in peers where !pairedMatches.contains(peer) {
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

    private func matchingPeersForPairedPhone() -> [HushPortPeer] {
        guard let pairedPhone else { return [] }
        return peers.filter { peer in
            peer.deviceID == pairedPhone.id
                || peer.name == pairedPhone.bonjourName
                || peer.name == pairedPhone.name
        }
    }

    private func resolvePairedPeerHost() async -> String? {
        for peer in matchingPeersForPairedPhone() {
            selectedPeer = peer
            if let host = await PeerEndpointResolver.resolveHost(for: peer) {
                return host
            }
            if let host = await pingAndWaitForPong(peer: peer, timeout: .milliseconds(1_200)) {
                return host
            }
        }
        return nil
    }

    private func seedHostFromPairingIfNeeded() {
        guard host.isEmpty else { return }
        guard !matchingPeersForPairedPhone().isEmpty else {
            if let address = pairedPhone?.networkAddress,
               isReachableStoredAddress(address) {
                host = address
            }
            return
        }
    }

    private func isReachableStoredAddress(_ address: String) -> Bool {
        guard !address.isEmpty else { return false }
        guard let macIP = NetworkAddress.localIPv4Address() else { return true }
        return NetworkAddress.isSameIPv4Subnet(macIP, address)
    }

    private func clearStalePairedAddressIfNeeded() {
        guard let macIP = NetworkAddress.localIPv4Address(),
              var device = pairedPhone,
              let stored = device.networkAddress,
              !stored.isEmpty else { return }
        guard !NetworkAddress.isSameIPv4Subnet(macIP, stored) else { return }
        if host == stored {
            host = ""
        }
        device.networkAddress = nil
        TrustedDeviceStore.save(device)
        pairedPhone = device
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

    private func pingAndWaitForPong(peer: HushPortPeer, timeout: Duration) async -> String? {
        pendingPongAddress = nil
        await sendPing(to: peer)

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
            allowStalePairedAddress: false
        )
    }

    func resolveStreamTarget() async -> StreamTargetResolver.Target? {
        var resolvedPeerHost: String?

        for peer in matchingPeersForPairedPhone() {
            if let host = await PeerEndpointResolver.resolveHost(for: peer) {
                resolvedPeerHost = host
                selectedPeer = peer
                updatePairedPhoneAddress(host, bonjourName: peer.name)
                break
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
            allowStalePairedAddress: false
        )
    }

    func disconnect() {
        streamGeneration &+= 1
        reconnectTask?.cancel()
        reconnectTask = nil
        streamTask?.cancel()
        streamTask = nil
        keepaliveTask?.cancel()
        keepaliveTask = nil
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
            let fromPairedPhone = event.message.senderID == pairedPhone?.id
                || event.message.senderName == pairedPhone?.name
                || event.message.senderName == pairedPhone?.bonjourName
            if fromPairedPhone {
                phoneReachable = true
            }
            if let address = resolvedPhoneAddress(from: event) {
                updatePairedPhoneAddress(
                    address,
                    bonjourName: selectedPeer?.name
                )
                if fromPairedPhone {
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
                self.clearStalePairedAddressIfNeeded()
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

    private func restartDiscovery() {
        discovery?.cancel()
        discovery = nil
        startDiscovery()
    }

    private func statusMessageForIdleState() -> String {
        if pairedPhone == nil {
            return "Scan the QR code with your iPhone"
        }
        if phoneReachable || !peers.isEmpty {
            if pairedPhone?.networkAddress == nil {
                return "iPhone found — resolving address…"
            }
            return "Ready — tap Stream Mac audio"
        }
        return "iPhone not discovered yet. Open HushPort on your iPhone."
    }

    private func startAddressRefreshLoop() {
        addressRefreshTask?.cancel()
        addressRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard pairedPhone != nil else { continue }
                guard phoneReachable || !peers.isEmpty else { continue }
                await refreshDiscoveredPhoneAddress()
                if !isSending {
                    status = statusMessageForIdleState()
                }
            }
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
            clearStalePairedAddressIfNeeded()
            invalidateRouteCacheForNetworkChange()
            restartDiscovery()
            Task { await refreshDiscoveredPhoneAddress() }
        } else if pairedPhone != nil {
            clearStalePairedAddressIfNeeded()
            Task { await refreshDiscoveredPhoneAddress() }
        }
        if isSending {
            status = "Network changed — reconnecting…"
            scheduleReconnect()
        } else if pairedPhone != nil {
            status = statusMessageForIdleState()
        }
    }

    private func invalidateRouteCacheForNetworkChange() {
        let storedAddress = pairedPhone?.networkAddress
        if host.isEmpty || host == storedAddress {
            host = ""
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
            guard !Task.isCancelled else { return }
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

    private func applyDiscoveredPhoneAddress(_ address: String, fromPairedPeer: Bool = false) {
        guard !address.isEmpty else { return }
        let previousPaired = pairedPhone?.networkAddress
        if fromPairedPeer || host.isEmpty || host == previousPaired {
            host = address
        }
        updatePairedPhoneAddress(address, bonjourName: selectedPeer?.name)
    }

    private func refreshDiscoveredPhoneAddress() async {
        guard pairedPhone != nil else { return }
        if let pairedHost = await resolvePairedPeerHost() {
            applyDiscoveredPhoneAddress(pairedHost, fromPairedPeer: true)
            return
        }
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
        if let address = pairedPhone.networkAddress, !address.isEmpty,
           host.isEmpty, matchingPeersForPairedPhone().isEmpty,
           isReachableStoredAddress(address) {
            host = address
        }
        if let match = peers.first(where: { $0.deviceID == pairedPhone.id || $0.name == pairedPhone.bonjourName }) {
            selectedPeer = match
        } else {
            selectedPeer = peers.first
        }
    }

    private func startStreaming(useTestTone: Bool, target: StreamTargetResolver.Target) {
        guard !Task.isCancelled else { return }
        streamTask?.cancel()
        keepaliveTask?.cancel()
        controlSender?.cancel()
        controlSender = nil
        streamGeneration &+= 1
        let generation = streamGeneration
        #if DEBUG
        print("[HushPort] stream generation \(generation) started")
        #endif
        isSending = true
        connectionState = .connecting
        packetsSent = 0
        currentStreamHost = target.host
        status = "Connecting to \(target.host)…"
        streamTask = Task {
            var ownedKeepalive: Task<Void, Never>?
            do {
                let sender = try UDPAudioSender(host: target.host, port: target.port)
                defer { sender.cancel() }
                try await sender.prepare()
                await notifyReceiver(at: target.host, generation: generation)
                var sequence: UInt32 = 0
                let clock = ContinuousClock()
                var nextDeadline = clock.now
                var phase = 0.0
                var silentCaptureFrames = 0
                var lastCapturedPayload: Data?
                let capture = useTestTone ? nil : try? SharedAudioCapture()
                if !useTestTone, capture == nil {
                    setStreamPresentationState(
                        generation: generation,
                        status: "HushPort Audio is not running. Select HushPort in System Settings → Sound → Output."
                    )
                }
                setStreamPresentationState(
                    generation: generation,
                    connectionState: .streaming,
                    status: useTestTone
                        ? "Sending test tone to \(target.host)"
                        : "Streaming Mac audio to \(target.host)"
                )
                ownedKeepalive = startKeepalive(to: target.host, generation: generation)
                let packetDuration = AudioStreamFormat.prototype.packetDuration
                while !Task.isCancelled, isCurrentStreamGeneration(generation) {
                    if clock.now < nextDeadline {
                        try await clock.sleep(until: nextDeadline, tolerance: .microseconds(250))
                    }
                    guard isCurrentStreamGeneration(generation) else { break }
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
                                generation: generation,
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
                    if isCurrentStreamGeneration(generation) {
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
                    generation: generation,
                    connectionState: .error(error.localizedDescription),
                    status: error.localizedDescription
                )
            }
            finishStreamSession(generation: generation, ownedKeepalive: ownedKeepalive)
        }
    }

    private func isCurrentStreamGeneration(_ generation: UInt64) -> Bool {
        generation == streamGeneration
    }

    private func setStreamPresentationState(
        generation: UInt64,
        connectionState: ConnectionState? = nil,
        status: String? = nil
    ) {
        guard isCurrentStreamGeneration(generation) else { return }
        if let connectionState {
            self.connectionState = connectionState
        }
        if let status {
            self.status = status
        }
    }

    private func finishStreamSession(generation: UInt64, ownedKeepalive: Task<Void, Never>?) {
        guard isCurrentStreamGeneration(generation) else {
            #if DEBUG
            print("[HushPort] stale stream generation \(generation) cleanup ignored; current=\(streamGeneration)")
            #endif
            return
        }
        ownedKeepalive?.cancel()
        keepaliveTask = nil
        streamTask = nil
        isSending = false
        currentStreamHost = nil
        if connectionState == .streaming {
            connectionState = .idle
        }
    }

    @discardableResult
    private func startKeepalive(to host: String, generation: UInt64) -> Task<Void, Never> {
        let keepalive = Task {
            while !Task.isCancelled, isCurrentStreamGeneration(generation) {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, isCurrentStreamGeneration(generation) else { break }
                await notifyReceiver(at: host, generation: generation)
            }
        }
        keepaliveTask = keepalive
        return keepalive
    }

    private func notifyReceiver(at host: String, generation: UInt64) async {
        guard isCurrentStreamGeneration(generation) else { return }
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
            setStreamPresentationState(
                generation: generation,
                status: "Streaming to \(host), but could not wake iPhone listener"
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
