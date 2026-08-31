#if os(iOS)
import SwiftUI
import UIKit

struct LabeledPairingField: View {
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
#endif
