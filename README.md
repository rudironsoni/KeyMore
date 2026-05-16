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

## Current Truth

- Tab and Esc are implemented as text-proxy fallbacks.
- Control and Option can produce terminal-style fallback text sequences for letter keys.
- Command is intentionally not mapped to shortcuts because a shortcut requires hardware-equivalent event delivery.
- Hardware-equivalent behavior is unproven until host diagnostics observe real physical-key responder events.
- KeyMore now generates USB HID keyboard reports for parity targets such as Cmd-C, Ctrl-Opt-Tab, and Esc.
- Current route assessment treats a real external HID bridge as the only non-private path that can plausibly target arbitrary apps with true modifier/key behavior.
