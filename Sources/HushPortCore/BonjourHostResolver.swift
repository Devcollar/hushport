import Foundation
import Network

#if canImport(Darwin)
import Darwin
#endif

enum BonjourHostResolver {
    static func resolveHost(from endpoint: NWEndpoint) async -> String? {
        guard case let .service(name, type, domain, _) = endpoint else { return nil }
        let normalizedType = type.hasSuffix(".") ? type : "\(type)."
        let normalizedDomain = domain.isEmpty ? "local." : (domain.hasSuffix(".") ? domain : "\(domain).")
        return await resolveNetService(name: name, type: normalizedType, domain: normalizedDomain)
    }

    private static func resolveNetService(name: String, type: String, domain: String) async -> String? {
        await withCheckedContinuation { continuation in
            final class Resolver: NSObject, NetServiceDelegate {
                private let service: NetService
                private var continuation: CheckedContinuation<String?, Never>?
                private var finished = false
                private var selfRetain: Resolver?

                init(
                    name: String,
                    type: String,
                    domain: String,
                    continuation: CheckedContinuation<String?, Never>
                ) {
                    service = NetService(domain: domain, type: type, name: name)
                    self.continuation = continuation
                    super.init()
                    service.delegate = self
                }

                func start() {
                    selfRetain = self
                    service.resolve(withTimeout: 5)
                }

                func netServiceDidResolve(_ sender: NetService) {
                    guard !finished else { return }
                    if let host = Self.ipv4Address(from: sender.addresses) {
                        finish(host)
                        return
                    }
                    finish(nil)
                }

                func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
                    finish(nil)
                }

                private func finish(_ host: String?) {
                    guard !finished else { return }
                    finished = true
                    service.stop()
                    continuation?.resume(returning: host)
                    continuation = nil
                    selfRetain = nil
                }

                private static func ipv4Address(from addresses: [Data]?) -> String? {
                    guard let addresses else { return nil }
                    for data in addresses {
                        if let host = ipv4String(from: data) {
                            return host
                        }
                    }
                    return nil
                }

                private static func ipv4String(from data: Data) -> String? {
                    data.withUnsafeBytes { rawBuffer in
                        guard rawBuffer.count >= MemoryLayout<sockaddr>.size else { return nil }
                        return rawBuffer.baseAddress?.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                            guard address.pointee.sa_family == sa_family_t(AF_INET) else { return nil }
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
                            guard result == 0 else { return nil }
                            return String(cString: host)
                        }
                    }
                }
            }

            let resolver = Resolver(name: name, type: type, domain: domain, continuation: continuation)
            resolver.start()
        }
    }
}
