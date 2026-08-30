#if os(iOS)
import SwiftUI

@main
struct HushPortIOSApp: App {
    var body: some Scene {
        WindowGroup {
            ReceiverView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
                .preferredColorScheme(.dark)
        }
    }
}
#else
@main enum HushPortIOSApp { static func main() {} }
#endif
