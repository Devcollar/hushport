#if os(macOS)
import HushPortCore
import SwiftUI

struct SenderView: View {
    @Bindable var session = MacSessionController.shared
    @State private var audioPluginInstaller = AudioPluginInstaller()

    var body: some View {
        Form {
            Section("This Mac") {
                LabeledContent("Network address", value: session.macAddress)
                LabeledContent("Network", value: session.networkStatus)
            }
            Section("Pair iPhone") {
                if let pairedPhone = session.pairedPhone {
                    LabeledContent("Paired with", value: pairedPhone.name)
                    LabeledContent("iPhone address", value: pairedPhone.networkAddress ?? "Unknown")
                    if let stored = pairedPhone.networkAddress,
                       !session.host.isEmpty,
                       stored != session.host {
                        Text("Using \(session.host) — saved address is \(stored).")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Button("Forget pairing", role: .destructive) {
                        session.forgetPairing()
                    }
                } else {
                    Text("Open HushPort on your iPhone and scan this QR code.")
                        .foregroundStyle(.secondary)
                    if let qrImage = session.pairingQRImage {
                        qrImage
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    Text(session.macPairingCode)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                    Text("If scanning fails, enter this code manually on your iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Refresh pairing code") {
                        session.refreshPairingOffer()
                    }
                }
            }
            Section("Nearby iPhone") {
                if session.pairedPhone != nil {
                    LabeledContent("Discovered nearby", value: session.phoneReachable ? "Yes" : "No")
                    Text("Shows whether your iPhone is advertising on this network — not whether it is on the same Wi-Fi.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if session.peers.isEmpty {
                    if session.pairedPhone != nil {
                        if session.pairedPhone?.networkAddress == nil {
                            Text("Forget pairing and pair again so HushPort can remember your iPhone address.")
                                .foregroundStyle(.secondary)
                        }
                        Text("Open HushPort on your iPhone and tap Start Listening if it does not appear.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Your iPhone will appear here after pairing.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Receiver", selection: $session.selectedPeer) {
                        ForEach(session.peers) { peer in
                            Text(peer.displayName).tag(Optional(peer))
                        }
                    }
                }
            }
            DisclosureGroup("Manual connection") {
                TextField("iPhone address", text: $session.host)
                TextField("UDP port", value: $session.port, format: .number.grouping(.never))
            }
            Section {
                HStack {
                    Button(session.isSending ? "Stop" : "Stream Mac audio") {
                        session.isSending ? session.disconnect() : session.connectAndStream()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Send test tone") {
                        session.isSending ? session.disconnect() : session.sendTestTone()
                    }
                    .disabled(session.isSending)
                }
                Text(session.status)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                if session.isSending {
                    Text("Packets sent: \(session.packetsSent.formatted())")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            Section("Mac audio output") {
                Text("Set System Settings → Sound → Output to HushPort before streaming video or music.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Button("Install or Update HushPort Audio") {
                    audioPluginInstaller.install()
                }
                .disabled(audioPluginInstaller.isInstalling)
                Text(audioPluginInstaller.status)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("HushPort Public Beta — free during evaluation. Report issues on GitHub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 620)
        .onAppear { session.refreshNetworkInfo() }
    }
}
#endif
