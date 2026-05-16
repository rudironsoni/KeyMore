import Foundation
import KeyMoreCore
import Network

final class HIDBridgeServer {
    typealias MessageHandler = (HIDBridgeMessage, HIDBridgeAck) -> Void
    typealias StateHandler = (String) -> Void

    private let queue = DispatchQueue(label: "KeyMore.HIDBridgeServer")
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: HIDBridgeConnectionSession] = [:]
    private let onMessage: MessageHandler
    private let onStateChange: StateHandler

    init(onStateChange: @escaping StateHandler, onMessage: @escaping MessageHandler) {
        self.onStateChange = onStateChange
        self.onMessage = onMessage
    }

    func start() {
        guard listener == nil else {
            return
        }

        do {
            let port = NWEndpoint.Port(rawValue: HIDBridgeConstants.loopbackPort)!
            let listener = try NWListener(using: .tcp, on: port)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state)
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }

            listener.start(queue: queue)
        } catch {
            onStateChange("HID bridge failed to bind: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for session in sessions.values {
            session.cancel()
        }
        sessions.removeAll()
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            onStateChange("HID bridge listening on \(HIDBridgeConstants.loopbackHost):\(HIDBridgeConstants.loopbackPort)")
        case .failed(let error):
            onStateChange("HID bridge listener failed: \(error.localizedDescription)")
            stop()
        case .cancelled:
            onStateChange("HID bridge stopped")
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let session = HIDBridgeConnectionSession(connection: connection) { [weak self] message in
            guard let self else {
                return HIDBridgeAck(
                    id: message.id,
                    accepted: false,
                    mode: .diagnosticAppSink,
                    outcome: .unknown,
                    detail: "Bridge server disappeared before dispatch."
                )
            }

            let ack = AppHIDBridgeDispatcher.dispatch(message)
            self.onMessage(message, ack)
            return ack
        } onClose: { [weak self, weak connection] in
            guard let connection else { return }
            self?.sessions.removeValue(forKey: ObjectIdentifier(connection))
        }

        sessions[ObjectIdentifier(connection)] = session
        session.start(queue: queue)
    }
}

private enum AppHIDBridgeDispatcher {
    static func dispatch(_ message: HIDBridgeMessage) -> HIDBridgeAck {
        HIDBridgeAck(
            id: message.id,
            accepted: true,
            mode: .diagnosticAppSink,
            outcome: .appIntegratedOnly,
            detail: "Received \(message.frames.count) HID frame(s). Public iOS APIs do not let the app inject them into arbitrary host apps."
        )
    }
}

private final class HIDBridgeConnectionSession {
    private let connection: NWConnection
    private let handleMessage: (HIDBridgeMessage) -> HIDBridgeAck
    private let onClose: () -> Void
    private var buffer = Data()

    init(
        connection: NWConnection,
        handleMessage: @escaping (HIDBridgeMessage) -> HIDBridgeAck,
        onClose: @escaping () -> Void
    ) {
        self.connection = connection
        self.handleMessage = handleMessage
        self.onClose = onClose
    }

    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.onClose()
            }
            if case .cancelled = state {
                self?.onClose()
            }
        }

        connection.start(queue: queue)
        receive()
    }

    func cancel() {
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }

            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drainBuffer()
            }

            if isComplete || error != nil {
                self.connection.cancel()
                self.onClose()
                return
            }

            self.receive()
        }
    }

    private func drainBuffer() {
        while let terminatorIndex = buffer.firstIndex(of: HIDBridgeConstants.frameTerminator) {
            let frame = buffer[..<terminatorIndex]
            buffer.removeSubrange(...terminatorIndex)
            process(Data(frame))
        }
    }

    private func process(_ data: Data) {
        do {
            let message = try HIDBridgeCodec.decodeMessage(data)
            let ack = handleMessage(message)
            let ackData = try HIDBridgeCodec.encode(ack)
            connection.send(content: ackData, completion: .contentProcessed { _ in })
        } catch {
            let detail = "Rejected malformed HID bridge frame: \(error.localizedDescription)"
            let fallbackAck = HIDBridgeAck(
                id: UUID(),
                accepted: false,
                mode: .diagnosticAppSink,
                outcome: .unknown,
                detail: detail
            )
            if let ackData = try? HIDBridgeCodec.encode(fallbackAck) {
                connection.send(content: ackData, completion: .contentProcessed { _ in })
            }
        }
    }
}
