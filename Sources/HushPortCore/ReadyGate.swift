import Foundation
import Network

final class ListenerReadyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isReady = false
    private var waiters: [CheckedContinuation<Void, Error>] = []

    func wait(for listener: NWListener) async throws {
        if lock.withLock({ isReady }) { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock {
                if isReady {
                    continuation.resume()
                    return
                }
                waiters.append(continuation)
            }
            let previousHandler = listener.stateUpdateHandler
            listener.stateUpdateHandler = { [weak self] state in
                previousHandler?(state)
                guard let self else { return }
                switch state {
                case .ready:
                    self.resumeAll()
                case .failed(let error):
                    self.failAll(UDPTransportError.listenerFailed(error.localizedDescription))
                case .cancelled:
                    self.failAll(UDPTransportError.notReady)
                default:
                    break
                }
            }
            if listener.state == .ready {
                self.resumeAll()
            }
        }
    }

    private func resumeAll() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            isReady = true
            let waiters = self.waiters
            self.waiters = []
            return waiters
        }
        pending.forEach { $0.resume() }
    }

    private func failAll(_ error: Error) {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            let waiters = self.waiters
            self.waiters = []
            return waiters
        }
        pending.forEach { $0.resume(throwing: error) }
    }
}

final class ReadyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isReady = false
    private var waiters: [CheckedContinuation<Void, Error>] = []

    func wait(for connection: NWConnection) async throws {
        if lock.withLock({ isReady }) { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock {
                if isReady {
                    continuation.resume()
                    return
                }
                waiters.append(continuation)
            }
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.resumeAll()
                case .failed(let error):
                    self.failAll(UDPTransportError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    self.failAll(UDPTransportError.notReady)
                default:
                    break
                }
            }
            if connection.state == .ready {
                self.resumeAll()
            }
        }
    }

    private func resumeAll() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            isReady = true
            let waiters = self.waiters
            self.waiters = []
            return waiters
        }
        pending.forEach { $0.resume() }
    }

    private func failAll(_ error: Error) {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            let waiters = self.waiters
            self.waiters = []
            return waiters
        }
        pending.forEach { $0.resume(throwing: error) }
    }
}
