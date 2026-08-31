#if os(iOS)
import SwiftUI

struct ManualPairingSheet: View {
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
#endif
