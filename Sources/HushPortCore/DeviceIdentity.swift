import Foundation

public struct DeviceIdentity: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public enum DeviceIdentityStore {
    private static let storageKey = "hushport.device.identity"

    public static func load(defaultName: String) -> DeviceIdentity {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let identity = try? JSONDecoder().decode(DeviceIdentity.self, from: data) else {
            let identity = DeviceIdentity(name: defaultName)
            save(identity)
            return identity
        }
        return identity
    }

    public static func save(_ identity: DeviceIdentity) {
        guard let data = try? JSONEncoder().encode(identity) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
