# KeyMore Context

## Glossary

### KeyMore Keyboard
The iOS custom keyboard extension provided by KeyMore. It replaces the active iOS software keyboard when the user selects it.

### Hardware-Equivalent Key
A key whose press, release, modifier state, and shortcut behavior are observed by the foreground app through the same responder path used by a physical external keyboard.

### Text-Proxy Key
A key implemented only through the custom keyboard extension text document proxy. It may insert or delete text, but it is not equivalent to a physical key event.

### Private-Path Probe
Internal-only diagnostic code that inspects undocumented event-injection surfaces to determine whether hardware-equivalent key behavior is possible on non-jailbroken devices.

### Feasibility Matrix
The evidence table that records whether each requested key can be delivered as hardware-equivalent input, text-proxy-only fallback, or is blocked by OS boundaries.

### Parity Route
A possible delivery path for external-keyboard behavior, such as public text proxy, CoreHID virtual device, private XCTest synthesis, private HID injection, a host-app hook, or real HID hardware.

### HID Report
The low-level keyboard report shape used by external keyboards to represent modifier bits and key usages.

### External HID Bridge
A separate hardware device that receives commands from KeyMore and presents itself to iOS/iPadOS as a real Bluetooth or USB keyboard.

### CoreHID Virtual Device
Apple's entitlement-gated software HID route. If `com.apple.developer.hid.virtual.device` is granted and available to the keyboard extension, KeyMore can attempt to dispatch HID keyboard reports without external hardware.
