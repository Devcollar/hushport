import Foundation

public struct MacPairingOffer: Equatable, Sendable {
    public let deviceID: UUID
    public let deviceName: String
    public let pairingCode: String
    public let hostAddress: String

    public init(deviceID: UUID, deviceName: String, pairingCode: String, hostAddress: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.pairingCode = pairingCode
        self.hostAddress = hostAddress
    }
}

public enum PairingPayload {
    public static func makeURL(offer: MacPairingOffer) -> String {
        var components = URLComponents()
        components.scheme = "hushport"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "id", value: offer.deviceID.uuidString),
            URLQueryItem(name: "name", value: offer.deviceName),
            URLQueryItem(name: "code", value: offer.pairingCode),
            URLQueryItem(name: "host", value: offer.hostAddress),
        ]
        return components.url?.absoluteString
            ?? "hushport://pair?id=\(offer.deviceID.uuidString)&code=\(offer.pairingCode)&host=\(offer.hostAddress)"
    }

    public static func parse(_ rawValue: String) -> MacPairingOffer? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "hushport", url.host == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return nil }

        func value(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        guard let idString = value("id"), let deviceID = UUID(uuidString: idString),
              let deviceName = value("name"),
              let pairingCode = value("code"),
              PairingCodeGenerator.isValid(pairingCode),
              let hostAddress = value("host"), !hostAddress.isEmpty else {
            return nil
        }
        return MacPairingOffer(
            deviceID: deviceID,
            deviceName: deviceName,
            pairingCode: pairingCode,
            hostAddress: hostAddress
        )
    }
}
