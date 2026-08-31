#if os(iOS)
import SwiftUI

struct ReceiverView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = ReceiverModel()
    @State private var showManualPairing = false
    @State private var showForgetConfirmation = false

    var body: some View {
        ZStack {
            appBackground

            if model.pairedMac == nil {
                PairingView(model: model, showManualPairing: $showManualPairing)
                    .transition(.opacity)
            } else {
                ReceiverDashboardView(model: model, showForgetConfirmation: $showForgetConfirmation)
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
}
#endif
