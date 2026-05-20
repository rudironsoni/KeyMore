import Foundation

public enum KeyEmissionOutcome: String, CaseIterable, Codable, Equatable, Sendable {
    case hardwareEquivalent = "hardware-equivalent"
    case textProxyOnly = "text-proxy-only"
    case blockedBySandbox = "blocked-by-sandbox"
    case blockedByEntitlement = "blocked-by-entitlement"
    case simulatorOnly = "simulator-only"
    case automationOnly = "automation-only"
    case appIntegratedOnly = "app-integrated-only"
    case hardwareBridgeRequired = "hardware-bridge-required"
    case missingRuntime = "missing-runtime"
    case unknown
}

public struct KeyFeasibilityRecord: Equatable, Identifiable {
    public var id: SpecialKey { key }
    public let key: SpecialKey
    public let publicFallback: String
    public let hardwareEquivalentTarget: String
    public let currentResult: KeyEmissionOutcome

    public init(
        key: SpecialKey,
        publicFallback: String,
        hardwareEquivalentTarget: String,
        currentResult: KeyEmissionOutcome
    ) {
        self.key = key
        self.publicFallback = publicFallback
        self.hardwareEquivalentTarget = hardwareEquivalentTarget
        self.currentResult = currentResult
    }
}

public enum KeyFeasibilityMatrix {
    public static let baseline: [KeyFeasibilityRecord] = [
        KeyFeasibilityRecord(
            key: .tab,
            publicFallback: "Insert tab character",
            hardwareEquivalentTarget: "Host receives Tab key press/release",
            currentResult: .textProxyOnly
        ),
        KeyFeasibilityRecord(
            key: .escape,
            publicFallback: "Insert escape character",
            hardwareEquivalentTarget: "Host receives Escape key press/release",
            currentResult: .textProxyOnly
        ),
        KeyFeasibilityRecord(
            key: .control,
            publicFallback: "Sticky modifier for control-character fallback",
            hardwareEquivalentTarget: "Host receives Control modifier state",
            currentResult: .unknown
        ),
        KeyFeasibilityRecord(
            key: .option,
            publicFallback: "Sticky modifier for escape-prefix fallback",
            hardwareEquivalentTarget: "Host receives Option modifier state",
            currentResult: .unknown
        ),
        KeyFeasibilityRecord(
            key: .command,
            publicFallback: "Visual/sticky state only",
            hardwareEquivalentTarget: "Host receives Command modifier state and shortcuts",
            currentResult: .unknown
        )
    ]
}

public enum ParityRoute: String, CaseIterable, Identifiable {
    case keyboardExtensionTextProxy
    case coreHIDVirtualDevice
    case privateXCTestSynthesis
    case privateIOKitHIDInjection
    case graphicsServicesGSEvent
    case hostAppPrivateHIDHook
    case externalHIDBridge

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keyboardExtensionTextProxy:
            return "Keyboard extension text proxy"
        case .coreHIDVirtualDevice:
            return "CoreHID virtual device"
        case .privateXCTestSynthesis:
            return "XCTest private event synthesis"
        case .privateIOKitHIDInjection:
            return "IOKit HID injection"
        case .graphicsServicesGSEvent:
            return "GraphicsServices GSEvent"
        case .hostAppPrivateHIDHook:
            return "Host-app private HID hook"
        case .externalHIDBridge:
            return "External HID bridge"
        }
    }
}

public struct ParityRouteAssessment: Equatable, Identifiable {
    public var id: ParityRoute { route }
    public let route: ParityRoute
    public let canTargetArbitraryApps: Bool
    public let requiresPrivateAPI: Bool
    public let requiresRestrictedEntitlement: Bool
    public let requiresExternalHardware: Bool
    public let expectedOutcome: KeyEmissionOutcome
    public let evidence: String

    public init(
        route: ParityRoute,
        canTargetArbitraryApps: Bool,
        requiresPrivateAPI: Bool,
        requiresRestrictedEntitlement: Bool = false,
        requiresExternalHardware: Bool,
        expectedOutcome: KeyEmissionOutcome,
        evidence: String
    ) {
        self.route = route
        self.canTargetArbitraryApps = canTargetArbitraryApps
        self.requiresPrivateAPI = requiresPrivateAPI
        self.requiresRestrictedEntitlement = requiresRestrictedEntitlement
        self.requiresExternalHardware = requiresExternalHardware
        self.expectedOutcome = expectedOutcome
        self.evidence = evidence
    }
}

public enum ParityRouteMatrix {
    public static let current: [ParityRouteAssessment] = [
        ParityRouteAssessment(
            route: .keyboardExtensionTextProxy,
            canTargetArbitraryApps: false,
            requiresPrivateAPI: false,
            requiresExternalHardware: false,
            expectedOutcome: .textProxyOnly,
            evidence: "Apple custom keyboard extensions provide text-document proxy operations, not hardware key dispatch."
        ),
        ParityRouteAssessment(
            route: .coreHIDVirtualDevice,
            canTargetArbitraryApps: true,
            requiresPrivateAPI: false,
            requiresRestrictedEntitlement: true,
            requiresExternalHardware: false,
            expectedOutcome: .blockedByEntitlement,
            evidence: "CoreHID can model a virtual keyboard and dispatch reports, but creating a virtual HID device requires Apple's com.apple.developer.hid.virtual.device entitlement."
        ),
        ParityRouteAssessment(
            route: .privateXCTestSynthesis,
            canTargetArbitraryApps: false,
            requiresPrivateAPI: true,
            requiresExternalHardware: false,
            expectedOutcome: .automationOnly,
            evidence: "WebDriverAgent/Appium use XCTest private event records; these are runner/automation surfaces, not extension product APIs."
        ),
        ParityRouteAssessment(
            route: .privateIOKitHIDInjection,
            canTargetArbitraryApps: true,
            requiresPrivateAPI: true,
            requiresExternalHardware: false,
            expectedOutcome: .blockedByEntitlement,
            evidence: "IOHID keyboard event construction is plausible, but dispatch normally crosses entitlement and sender-id boundaries."
        ),
        ParityRouteAssessment(
            route: .graphicsServicesGSEvent,
            canTargetArbitraryApps: false,
            requiresPrivateAPI: true,
            requiresExternalHardware: false,
            expectedOutcome: .unknown,
            evidence: "Older physical-key event inspection points at UIInternalEvent/GSEvent; construction and cross-app delivery remain unproven."
        ),
        ParityRouteAssessment(
            route: .hostAppPrivateHIDHook,
            canTargetArbitraryApps: false,
            requiresPrivateAPI: true,
            requiresExternalHardware: false,
            expectedOutcome: .appIntegratedOnly,
            evidence: "Reverse-engineering reports describe feeding IOHID events into a host app private handler; this requires the host app to cooperate or be hooked."
        ),
        ParityRouteAssessment(
            route: .externalHIDBridge,
            canTargetArbitraryApps: true,
            requiresPrivateAPI: false,
            requiresExternalHardware: true,
            expectedOutcome: .hardwareBridgeRequired,
            evidence: "A real BLE/USB HID bridge is seen by iOS as an external keyboard and can deliver genuine modifier/key reports."
        )
    ]
}
