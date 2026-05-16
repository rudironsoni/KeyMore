import Foundation
import KeyMoreCore
import Network
import os

final class HIDBridgeClient {
    static let shared = HIDBridgeClient()

    private let logger = Logger(subsystem: "com.rudironsoni.KeyMore.Keyboard", category: "HIDBridgeClient")
    private let queue = DispatchQueue(label: "KeyMore.HIDBridgeClient")
    private var activeConnections: [UUID: NWConnection] = [:]

    private init() {}

    func send(_ message: HIDBridgeMessage) {
        guard let data = try? HIDBridgeCodec.encode(message),
              let port = NWEndpoint.Port(rawValue: HIDBridgeConstants.loopbackPort) else {
            logger.error("bridge encode failed key=\(message.keyLabel, privacy: .public)")
            return
        }

        logger.info("bridge send queued key=\(message.keyLabel, privacy: .public) frames=\(message.frames.count, privacy: .public)")

        queue.async { [weak self] in
            guard let self else {
                return
            }

            let connectionID = message.id
            let connection = NWConnection(
                host: NWEndpoint.Host(HIDBridgeConstants.loopbackHost),
                port: port,
                using: .tcp
            )
            self.activeConnections[connectionID] = connection

            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let connection else {
                    return
                }

                switch state {
                case .ready:
                    self?.logger.info("bridge ready key=\(message.keyLabel, privacy: .public)")
                    connection.send(content: data, completion: .contentProcessed { [weak self, weak connection] _ in
                        connection?.receive(minimumIncompleteLength: 1, maximumLength: 2_048) { _, _, _, _ in
                            self?.logger.info("bridge ack/close key=\(message.keyLabel, privacy: .public)")
                            connection?.cancel()
                            self?.finish(connectionID)
                        }
                    })
                case .failed(let error):
                    self?.logger.error("bridge failed key=\(message.keyLabel, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                    connection.cancel()
                    self?.finish(connectionID)
                case .cancelled:
                    self?.logger.info("bridge cancelled key=\(message.keyLabel, privacy: .public)")
                    connection.cancel()
                    self?.finish(connectionID)
                default:
                    break
                }
            }

            connection.start(queue: self.queue)
        }
    }

    private func finish(_ id: UUID) {
        queue.async { [weak self] in
            self?.activeConnections.removeValue(forKey: id)
        }
    }
}
