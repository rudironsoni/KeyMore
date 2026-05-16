import Darwin
import Foundation
import ObjectiveC

public enum RuntimeProbeKind: Equatable {
    case dynamicLibrarySymbol
    case objectiveCClass
    case objectiveCInstanceMethod(className: String)
    case objectiveCClassMethod(className: String)
}

public struct RuntimeProbeCandidate: Equatable, Identifiable {
    public var id: String { "\(route.rawValue)::\(displayName)" }
    public let route: ParityRoute
    public let kind: RuntimeProbeKind
    public let frameworkPath: String?
    public let symbol: String
    public let purpose: String

    public init(
        route: ParityRoute,
        kind: RuntimeProbeKind,
        frameworkPath: String? = nil,
        symbol: String,
        purpose: String
    ) {
        self.route = route
        self.kind = kind
        self.frameworkPath = frameworkPath
        self.symbol = symbol
        self.purpose = purpose
    }

    public var displayName: String {
        switch kind {
        case .dynamicLibrarySymbol:
            return "\(frameworkPath ?? "<process>")::\(symbol)"
        case .objectiveCClass:
            return "class \(symbol)"
        case .objectiveCInstanceMethod(let className):
            return "-[\(className) \(symbol)]"
        case .objectiveCClassMethod(let className):
            return "+[\(className) \(symbol)]"
        }
    }
}

public struct PrivatePathProbeResult: Equatable, Identifiable {
    public var id: String { candidate.id }
    public let candidate: RuntimeProbeCandidate
    public let outcome: KeyEmissionOutcome
    public let detail: String

    public init(candidate: RuntimeProbeCandidate, outcome: KeyEmissionOutcome, detail: String) {
        self.candidate = candidate
        self.outcome = outcome
        self.detail = detail
    }
}

public enum PrivatePathProbe {
    public static let candidates: [RuntimeProbeCandidate] = [
        RuntimeProbeCandidate(
            route: .graphicsServicesGSEvent,
            kind: .dynamicLibrarySymbol,
            frameworkPath: "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices",
            symbol: "GSEventCreateKeyEvent",
            purpose: "Construct legacy GraphicsServices key events"
        ),
        RuntimeProbeCandidate(
            route: .graphicsServicesGSEvent,
            kind: .dynamicLibrarySymbol,
            frameworkPath: "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices",
            symbol: "GSEventGetGSEventRecord",
            purpose: "Inspect physical-key GSEvent payloads"
        ),
        RuntimeProbeCandidate(
            route: .graphicsServicesGSEvent,
            kind: .objectiveCInstanceMethod(className: "UIEvent"),
            symbol: "_gsEvent",
            purpose: "Recover the private GSEvent backing a UIKit event"
        ),
        RuntimeProbeCandidate(
            route: .privateIOKitHIDInjection,
            kind: .dynamicLibrarySymbol,
            frameworkPath: "/System/Library/Frameworks/IOKit.framework/IOKit",
            symbol: "IOHIDEventCreateKeyboardEvent",
            purpose: "Construct low-level HID keyboard events"
        ),
        RuntimeProbeCandidate(
            route: .privateIOKitHIDInjection,
            kind: .dynamicLibrarySymbol,
            frameworkPath: "/System/Library/Frameworks/IOKit.framework/IOKit",
            symbol: "IOHIDEventSetSenderID",
            purpose: "Assign sender identity to low-level HID events"
        ),
        RuntimeProbeCandidate(
            route: .privateIOKitHIDInjection,
            kind: .dynamicLibrarySymbol,
            frameworkPath: "/System/Library/Frameworks/IOKit.framework/IOKit",
            symbol: "IOHIDEventSystemClientDispatchEvent",
            purpose: "Dispatch HID events into the system event pipeline"
        ),
        RuntimeProbeCandidate(
            route: .hostAppPrivateHIDHook,
            kind: .objectiveCInstanceMethod(className: "UIApplication"),
            symbol: "_handleHIDEvent:",
            purpose: "Feed a constructed HID event into a cooperating host app"
        ),
        RuntimeProbeCandidate(
            route: .privateXCTestSynthesis,
            kind: .objectiveCClass,
            symbol: "XCPointerEventPath",
            purpose: "Build private XCTest pointer/text input event paths"
        ),
        RuntimeProbeCandidate(
            route: .privateXCTestSynthesis,
            kind: .objectiveCInstanceMethod(className: "XCPointerEventPath"),
            symbol: "initForTextInput",
            purpose: "Create a keyboard/text-input XCTest event path"
        ),
        RuntimeProbeCandidate(
            route: .privateXCTestSynthesis,
            kind: .objectiveCInstanceMethod(className: "XCPointerEventPath"),
            symbol: "typeKey:modifiers:atOffset:",
            purpose: "Add a private XCTest key event"
        ),
        RuntimeProbeCandidate(
            route: .privateXCTestSynthesis,
            kind: .objectiveCInstanceMethod(className: "XCPointerEventPath"),
            symbol: "setModifiers:mergeWithCurrentModifierFlags:atOffset:",
            purpose: "Set private XCTest modifier state"
        ),
        RuntimeProbeCandidate(
            route: .privateXCTestSynthesis,
            kind: .objectiveCClass,
            symbol: "XCSynthesizedEventRecord",
            purpose: "Collect private XCTest event paths"
        ),
        RuntimeProbeCandidate(
            route: .privateXCTestSynthesis,
            kind: .objectiveCInstanceMethod(className: "XCSynthesizedEventRecord"),
            symbol: "synthesizeWithError:",
            purpose: "Submit private XCTest event records"
        ),
        RuntimeProbeCandidate(
            route: .privateIOKitHIDInjection,
            kind: .dynamicLibrarySymbol,
            frameworkPath: "/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices",
            symbol: "BKSHIDEventSetDigitizerInfo",
            purpose: "Check BackBoardServices HID mutation access"
        )
    ]

    public static func inspect(
        lookup: (RuntimeProbeCandidate) -> Bool = defaultRuntimeLookup
    ) -> [PrivatePathProbeResult] {
        candidates.map { candidate in
            if lookup(candidate) {
                return PrivatePathProbeResult(
                    candidate: candidate,
                    outcome: candidate.route == .privateXCTestSynthesis ? .automationOnly : .unknown,
                    detail: "Runtime surface is present; delivery still needs a separate send proof."
                )
            }

            return PrivatePathProbeResult(
                candidate: candidate,
                outcome: .missingRuntime,
                detail: "Runtime surface is not visible from this process."
            )
        }
    }

    public static func defaultRuntimeLookup(_ candidate: RuntimeProbeCandidate) -> Bool {
        switch candidate.kind {
        case .dynamicLibrarySymbol:
            return lookupDynamicLibrarySymbol(candidate)
        case .objectiveCClass:
            return NSClassFromString(candidate.symbol) != nil
        case .objectiveCInstanceMethod(let className):
            guard let cls = NSClassFromString(className) else {
                return false
            }
            return class_getInstanceMethod(cls, NSSelectorFromString(candidate.symbol)) != nil
        case .objectiveCClassMethod(let className):
            guard let cls = NSClassFromString(className),
                  let metaClass = object_getClass(cls) else {
                return false
            }
            return class_getClassMethod(metaClass, NSSelectorFromString(candidate.symbol)) != nil
        }
    }

    private static func lookupDynamicLibrarySymbol(_ candidate: RuntimeProbeCandidate) -> Bool {
        guard let frameworkPath = candidate.frameworkPath,
              let handle = dlopen(frameworkPath, RTLD_NOW) else {
            return false
        }
        defer { dlclose(handle) }
        return dlsym(handle, candidate.symbol) != nil
    }
}
