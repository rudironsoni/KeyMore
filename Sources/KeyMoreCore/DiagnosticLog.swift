import Foundation

public enum DiagnosticEventKind: String, Equatable {
    case pressBegan
    case pressEnded
    case keyCommand
    case textProxyFallback
    case hidBridge
    case privatePathProbe
}

public struct DiagnosticEvent: Equatable, Identifiable {
    public let id: UUID
    public let kind: DiagnosticEventKind
    public let summary: String
    public let outcome: KeyEmissionOutcome?

    public init(
        id: UUID = UUID(),
        kind: DiagnosticEventKind,
        summary: String,
        outcome: KeyEmissionOutcome? = nil
    ) {
        self.id = id
        self.kind = kind
        self.summary = summary
        self.outcome = outcome
    }
}

public final class DiagnosticLog {
    public private(set) var events: [DiagnosticEvent] = []

    public init() {}

    public func append(_ event: DiagnosticEvent) {
        events.append(event)
    }
}
