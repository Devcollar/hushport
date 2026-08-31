import Foundation

public struct TrustedDevice: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let pairedAt: Date
    public var bonjourName: String?
    /// Last-known IPv4 for display/debug only. Automatic routing uses Bonjour endpoints.
    public var networkAddress: String?

    public init(
        id: UUID,
        name: String,
        pairedAt: Date = .now,
        bonjourName: String? = nil,
        networkAddress: String? = nil
    ) {
        self.id = id
        self.name = name
        self.pairedAt = pairedAt
        self.bonjourName = bonjourName
        self.networkAddress = networkAddress
    }
}

public enum TrustedDeviceStore {
    private static let storageKey = "hushport.trusted.devices"

    public static func loadAll() -> [TrustedDevice] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let devices = try? JSONDecoder().decode([TrustedDevice].self, from: data) else {
            return []
        }
        return devices
    }

    public static func primary() -> TrustedDevice? {
        loadAll().first
    }

    @available(*, deprecated, renamed: "primary")
    public static func primaryPhone() -> TrustedDevice? { primary() }

    public static func save(_ device: TrustedDevice) {
        var devices = loadAll().filter { $0.id != device.id }
        devices.insert(device, at: 0)
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    public static func updateNetworkAddress(id: UUID, networkAddress: String, bonjourName: String? = nil) {
        var devices = loadAll()
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].networkAddress = networkAddress
        if let bonjourName {
            devices[index].bonjourName = bonjourName
        }
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    public static func remove(id: UUID) {
        let devices = loadAll().filter { $0.id != id }
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
