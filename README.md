# KeyMore

KeyMore is an internal feasibility project for an iOS/iPadOS keyboard with extra Tab, Esc, Control, Option, and Command keys.

The current milestone does not claim external-keyboard equivalence. It provides a custom keyboard extension, a diagnostics host app, and a private-path probe matrix to determine whether non-jailbroken iOS can deliver real hardware-equivalent key events from an on-screen keyboard.

## Build

Generate the Xcode project:

```sh
xcodegen generate
```

Run the core tests:

```sh
xcodebuild -project KeyMore.xcodeproj -scheme KeyMoreCore -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Use `xcsift` when running Xcode commands locally for concise diagnostics.

## CoreHID Virtual Keyboard

The experimental software parity route is implemented in `VirtualHIDKeyboardDispatcher`. `project.yml` signs the keyboard extension with `KeyboardExtension/KeyMoreKeyboard.VirtualHID.entitlements`, which requests `com.apple.developer.hid.virtual.device`. Simulator builds accept the entitlement key, but on-device signing still requires Apple to grant the capability to the development team provisioning profile.

## Current Truth

- Tab and Esc are implemented as text-proxy fallbacks.
- Control and Option can produce terminal-style fallback text sequences for letter keys.
- Command is intentionally not mapped to shortcuts because a shortcut requires hardware-equivalent event delivery.
- Hardware-equivalent behavior is unproven until host diagnostics observe real physical-key responder events.
- KeyMore now generates USB HID keyboard reports for parity targets such as Cmd-C, Ctrl-Opt-Tab, and Esc.
- KeyMore now includes an experimental CoreHID virtual-keyboard dispatcher. It requires OS support and Apple's `com.apple.developer.hid.virtual.device` entitlement; without that, the keyboard falls back to text-proxy behavior.
- Current route assessment treats CoreHID virtual HID as the software route to pursue with Apple, and a real external HID bridge as the only non-entitlement path that can plausibly target arbitrary apps with true modifier/key behavior.
