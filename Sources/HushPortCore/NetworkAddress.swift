import Foundation

public enum NetworkAddress {
    /// Returns the best local IPv4 address for LAN streaming.
    public static func localIPv4Address() -> String? {
        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddresses) == 0, let first = interfaceAddresses else {
            return nil
        }
        defer { freeifaddrs(interfaceAddresses) }

        var candidates: [(name: String, address: String)] = []
        for cursor in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = cursor.pointee
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let ip = String(cString: host)
            guard !ip.hasPrefix("127."), !ip.hasPrefix("169.254.") else { continue }

            let name = String(cString: interface.ifa_name)
            guard !name.hasPrefix("utun"), !name.hasPrefix("bridge"), name != "lo0" else { continue }
            candidates.append((name, ip))
        }

        for preferred in ["en0", "en1", "en2"] {
            if let match = candidates.first(where: { $0.name == preferred }) {
                return match.address
            }
        }
        if let wifiLike = candidates.first(where: { $0.name.hasPrefix("en") }) {
            return wifiLike.address
        }
        return candidates.first?.address
    }
}
