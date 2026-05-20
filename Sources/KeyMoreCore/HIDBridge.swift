import Foundation

public enum HIDBridgeConstants {
    public static let loopbackHost = "127.0.0.1"
    public static let loopbackPort: UInt16 = 47765
    public static let frameTerminator: UInt8 = 0x0A
}

public enum HIDBridgeFramePhase: String, Codable, Equatable, Sendable {
    case keyDown
    case keyUp
    case modifierState
}

public struct HIDBridgeFrame: Codable, Equatable, Sendable {
    public let phase: HIDBridgeFramePhase
    public let bytes: [UInt8]

    public init(phase: HIDBridgeFramePhase, bytes: [UInt8]) {
        self.phase = phase
        self.bytes = bytes
    }

    public init(phase: HIDBridgeFramePhase, report: HIDKeyboardReport) {
        self.init(phase: phase, bytes: report.bytes)
    }
}

public enum HIDBridgeSource: String, Codable, Equatable, Sendable {
    case keyboardExtension
    case diagnosticsApp
}

public enum HIDBridgeDispatchMode: String, Codable, Equatable, Sendable {
    case diagnosticAppSink
    case appIntegratedSink
    case coreHIDVirtualDevice
    case externalHardwareBridge
    case privateSystemDispatcher
}

public struct HIDBridgeMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let source: HIDBridgeSource
    public let keyLabel: String
    public let frames: [HIDBridgeFrame]
    public let fallbackAction: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        source: HIDBridgeSource,
        keyLabel: String,
        frames: [HIDBridgeFrame],
        fallbackAction: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.keyLabel = keyLabel
        self.frames = frames
        self.fallbackAction = fallbackAction
    }

    public static func keyPress(
        keyLabel: String,
        keyPress: HIDKeyPress,
        fallbackAction: String? = nil,
        source: HIDBridgeSource = .keyboardExtension
    ) -> HIDBridgeMessage {
        HIDBridgeMessage(
            source: source,
            keyLabel: keyLabel,
            frames: [
                HIDBridgeFrame(phase: .keyDown, report: keyPress.down),
                HIDBridgeFrame(phase: .keyUp, report: keyPress.up)
            ],
            fallbackAction: fallbackAction
        )
    }

    public static func modifierState(
        keyLabel: String,
        report: HIDKeyboardReport,
        fallbackAction: String? = nil,
        source: HIDBridgeSource = .keyboardExtension
    ) -> HIDBridgeMessage {
        HIDBridgeMessage(
            source: source,
            keyLabel: keyLabel,
            frames: [
                HIDBridgeFrame(phase: .modifierState, report: report)
            ],
            fallbackAction: fallbackAction
        )
    }
}

public struct HIDBridgeAck: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let accepted: Bool
    public let mode: HIDBridgeDispatchMode
    public let outcome: KeyEmissionOutcome
    public let detail: String

    public init(
        id: UUID,
        accepted: Bool,
        mode: HIDBridgeDispatchMode,
        outcome: KeyEmissionOutcome,
        detail: String
    ) {
        self.id = id
        self.accepted = accepted
        self.mode = mode
        self.outcome = outcome
        self.detail = detail
    }
}

public enum HIDBridgeCodec {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func encode(_ message: HIDBridgeMessage) throws -> Data {
        try lineDelimited(encoder.encode(message))
    }

    public static func encode(_ ack: HIDBridgeAck) throws -> Data {
        try lineDelimited(encoder.encode(ack))
    }

    public static func decodeMessage(_ data: Data) throws -> HIDBridgeMessage {
        try decoder.decode(HIDBridgeMessage.self, from: trimLineTerminator(data))
    }

    public static func decodeAck(_ data: Data) throws -> HIDBridgeAck {
        try decoder.decode(HIDBridgeAck.self, from: trimLineTerminator(data))
    }

    private static func lineDelimited(_ data: Data) throws -> Data {
        var output = data
        output.append(HIDBridgeConstants.frameTerminator)
        return output
    }

    private static func trimLineTerminator(_ data: Data) -> Data {
        var output = data
        while output.last == HIDBridgeConstants.frameTerminator {
            output.removeLast()
        }
        return output
    }
}
