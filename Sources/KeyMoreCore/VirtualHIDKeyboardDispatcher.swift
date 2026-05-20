import Foundation

#if canImport(CoreHID)
import CoreHID
#endif

#if canImport(Security)
import Security
#endif

public enum VirtualHIDDispatchResult: Equatable, Sendable {
    case dispatched
    case unavailable(String)
    case entitlementMissing(String)
    case failed(String)

    public var outcome: KeyEmissionOutcome {
        switch self {
        case .dispatched:
            return .hardwareEquivalent
        case .unavailable:
            return .missingRuntime
        case .entitlementMissing:
            return .blockedByEntitlement
        case .failed:
            return .unknown
        }
    }

    public var shouldApplyTextProxyFallback: Bool {
        self != .dispatched
    }

    public var detail: String {
        switch self {
        case .dispatched:
            return "CoreHID virtual keyboard report dispatched."
        case .unavailable(let detail), .entitlementMissing(let detail), .failed(let detail):
            return detail
        }
    }
}

public final class VirtualHIDKeyboardDispatcher: @unchecked Sendable {
    public static let shared = VirtualHIDKeyboardDispatcher()

    private init() {}

    public func dispatch(
        _ message: HIDBridgeMessage,
        completion: @escaping @Sendable (VirtualHIDDispatchResult) -> Void
    ) {
#if canImport(CoreHID)
        if #available(iOS 17.0, iOSApplicationExtension 17.0, macOS 15.0, *) {
            Task {
                let result = await CoreHIDVirtualKeyboard.shared.dispatch(message)
                completion(result)
            }
        } else {
            completion(.unavailable("CoreHID virtual HID requires an OS version with HIDVirtualDevice support."))
        }
#else
        completion(.unavailable("CoreHID is not available in this SDK."))
#endif
    }
}

#if canImport(CoreHID)
@available(iOS 17.0, iOSApplicationExtension 17.0, macOS 15.0, *)
private actor CoreHIDVirtualKeyboard {
    static let shared = CoreHIDVirtualKeyboard()

    private let delegate = CoreHIDVirtualKeyboardDelegate()
    private var device: HIDVirtualDevice?
    private var activationFailure: VirtualHIDDispatchResult?

    func dispatch(_ message: HIDBridgeMessage) async -> VirtualHIDDispatchResult {
        guard !message.frames.isEmpty else {
            return .failed("HID bridge message contains no frames.")
        }

        if let activationFailure {
            return activationFailure
        }

        guard let device = await activatedDevice() else {
            let result = VirtualHIDDispatchResult.entitlementMissing(
                "CoreHID could not create a virtual keyboard. The app or extension likely lacks com.apple.developer.hid.virtual.device, or the platform denies virtual HID creation."
            )
            activationFailure = result
            return result
        }

        do {
            for (index, frame) in message.frames.enumerated() {
                if index > 0 {
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                try await device.dispatchInputReport(data: Data(frame.bytes), timestamp: SuspendingClock.now)
            }
            return .dispatched
        } catch {
            return .failed("CoreHID dispatch failed: \(error.localizedDescription)")
        }
    }

    private func activatedDevice() async -> HIDVirtualDevice? {
        if let device {
            return device
        }

        guard Self.hasVirtualHIDEntitlement() else {
            return nil
        }

        let properties = HIDVirtualDevice.Properties(
            descriptor: Data(HIDKeyboardReportDescriptor.bootKeyboard),
            vendorID: 0x1209,
            productID: 0x4B4D,
            transport: .virtual,
            product: "KeyMore Virtual Keyboard",
            manufacturer: "KeyMore",
            modelNumber: "KeyMoreVirtualKeyboard",
            versionNumber: 1,
            serialNumber: "KeyMoreVirtualKeyboard",
            uniqueID: "com.rudironsoni.KeyMore.VirtualKeyboard",
            locationID: nil,
            localizationCode: nil,
            extraProperties: nil
        )

        guard let newDevice = HIDVirtualDevice(properties: properties) else {
            return nil
        }

        await newDevice.activate(delegate: delegate)
        device = newDevice
        return newDevice
    }

    private static func hasVirtualHIDEntitlement() -> Bool {
#if canImport(Security)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.hid.virtual.device" as CFString,
                nil
              ) else {
            return false
        }
        return (value as? Bool) == true
#else
        return true
#endif
    }
}

@available(iOS 17.0, iOSApplicationExtension 17.0, macOS 15.0, *)
private final class CoreHIDVirtualKeyboardDelegate: HIDVirtualDeviceDelegate, @unchecked Sendable {
    func hidVirtualDevice(
        _ device: HIDVirtualDevice,
        receivedSetReportRequestOfType type: HIDReportType,
        id: HIDReportID?,
        data: Data
    ) throws {}

    func hidVirtualDevice(
        _ device: HIDVirtualDevice,
        receivedGetReportRequestOfType type: HIDReportType,
        id: HIDReportID?,
        maxSize: size_t
    ) throws -> Data {
        Data(repeating: 0, count: maxSize)
    }
}
#endif
