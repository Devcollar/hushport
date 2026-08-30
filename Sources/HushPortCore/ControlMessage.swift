import Foundation

public enum ControlMessageType: String, Codable, Sendable {
    case pairRequest
    case pairAccept
    case pairReject
    case mute
    case unmute
    case ping
    case pong
    case unpair
}

public struct ControlMessage: Codable, Equatable, Sendable {
    public let type: ControlMessageType
    public let senderID: UUID
    public let senderName: String
    public let pairingCode: String?
    public let muted: Bool?
    /// Sender's current LAN IPv4 address, when known.
    public let networkAddress: String?

    public init(
        type: ControlMessageType,
        senderID: UUID,
        senderName: String,
        pairingCode: String? = nil,
        muted: Bool? = nil,
        networkAddress: String? = nil
    ) {
        self.type = type
        self.senderID = senderID
        self.senderName = senderName
        self.pairingCode = pairingCode
        self.muted = muted
        self.networkAddress = networkAddress
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public init(decoding data: Data) throws {
        self = try JSONDecoder().decode(ControlMessage.self, from: data)
    }
}

public enum PairingCodeGenerator {
    public static func makeCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    public static func isValid(_ code: String) -> Bool {
        code.count == 6 && code.allSatisfy(\.isNumber)
    }
}
