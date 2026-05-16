import Foundation

public enum SpecialKey: String, CaseIterable, Identifiable {
    case escape
    case control
    case option
    case command
    case tab

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .escape:
            return "esc"
        case .control:
            return "ctrl"
        case .option:
            return "opt"
        case .command:
            return "cmd"
        case .tab:
            return "tab"
        }
    }
}

