# KeyMore Private Key Event Feasibility

## Goal
Determine whether a non-jailbroken iOS/iPadOS custom keyboard extension can make on-screen Tab, Esc, Control, Option, and Command behave like real external keyboard keys in arbitrary host apps.

## Current Boundary
Public custom keyboard extensions can draw keys and use `UITextDocumentProxy` to insert or delete text. That supports text-proxy fallbacks such as inserting a tab character, but it does not prove hardware-equivalent key delivery.

## Probe Matrix

| Key | Public fallback | Hardware-equivalent target | Current result |
| --- | --- | --- | --- |
| Tab | Insert tab character | Host receives Tab key press/release | Text-proxy-only pending device proof |
| Esc | Insert escape character | Host receives Escape key press/release | Text-proxy-only pending device proof |
| Control | Sticky modifier for control-character fallback | Host receives Control modifier state | Unknown pending private probe |
| Option | Sticky modifier for escape-prefix fallback | Host receives Option modifier state | Unknown pending private probe |
| Command | Visual/sticky state only | Host receives Command modifier state and shortcuts | Unknown pending private probe |

## Probe Categories

- Public text proxy: verifies what the keyboard extension can do without private APIs.
- Host diagnostics: verifies what a real external keyboard looks like in the containing app.
- Private symbol inspection: checks whether relevant private frameworks and symbols are present in the process, without claiming event injection works.
- Private Objective-C runtime inspection: checks whether XCTest, UIKit, and other private classes/selectors are present in the running process.
- HID report generation: verifies that KeyMore can produce the same modifier/usage byte reports an external keyboard would send, even before a delivery path exists.
- Cross-app checks: records whether behavior survives outside the diagnostics host.

## Evidence Labels

- `hardware-equivalent`: host receives the same responder event shape as a physical keyboard.
- `text-proxy-only`: behavior is limited to inserted/deleted text or cursor movement.
- `blocked-by-sandbox`: the OS denies access from the app or keyboard extension sandbox.
- `blocked-by-entitlement`: the OS requires an entitlement unavailable to this app.
- `simulator-only`: behavior works in simulator/test tooling but not on physical devices.
- `automation-only`: behavior is limited to XCTest/WebDriverAgent-style automation contexts.
- `app-integrated-only`: behavior requires code or hooks inside the foreground app.
- `hardware-bridge-required`: behavior requires a real external HID device or dongle.
- `missing-runtime`: the inspected private class, selector, framework, or symbol is not visible from the current process.
- `unknown`: not yet proven.

## Internet Research Findings

### Public custom keyboard API

Apple's custom keyboard guide keeps the public surface centered on replacing the system keyboard and inserting/deleting text through `UITextDocumentProxy`. It also documents hard exclusions: secure text fields, phone-pad fields, and host apps that reject third-party keyboards. This route remains `text-proxy-only`.

Source:
- https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html

### Host-side physical-key APIs

Apple documents physical keyboard input as responder-chain press events, with `UIPress.key` populated for physical keyboard events, and shortcut handling through `UIKeyCommand`. That gives KeyMore a correct diagnostics target: the containing app must observe `pressesBegan`, `pressesEnded`, and `UIKeyCommand` if a route is truly hardware-equivalent.

Sources:
- https://developer.apple.com/documentation/uikit/handling-key-presses-made-on-a-physical-keyboard
- https://developer.apple.com/documentation/uikit/uipress/key
- https://developer.apple.com/documentation/uikit/uiresponder/keycommands

### XCTest/WebDriverAgent private synthesis

Appium documents that WebDriverAgent uses private XCTest event APIs such as `XCPointerEventPath` and `XCSynthesizedEventRecord`; the raw headers include keyboard-oriented methods such as `initForTextInput`, `typeKey:modifiers:atOffset:`, and `setModifiers:mergeWithCurrentModifierFlags:atOffset:`. This is promising for test automation and simulator/device-farm proof, but not a product path for a keyboard extension.

Sources:
- https://appium.github.io/appium-xcuitest-driver/8.3/guides/input-events/
- https://github.com/appium/WebDriverAgent/tree/master/PrivateHeaders/XCTest
- https://raw.githubusercontent.com/appium/WebDriverAgent/master/PrivateHeaders/XCTest/XCPointerEventPath.h
- https://raw.githubusercontent.com/appium/WebDriverAgent/master/PrivateHeaders/XCTest/XCSynthesizedEventRecord.h

### IOKit and host-app private hooks

Reverse-engineering discussion points to `IOHIDEventCreateKeyboardEvent` and, for non-jailbroken app-integrated tests, feeding a constructed event into a private host-app handler such as `_handleHIDEvent:`. This is not arbitrary-app keyboard-extension parity; it is either app-integrated, entitlement blocked, or jailbreak/daemon shaped.

Sources:
- https://iosre.com/t/ios%E5%A6%82%E4%BD%95%E6%A8%A1%E6%8B%9F%E9%94%AE%E7%9B%98%E5%9B%9E%E8%BD%A6%E9%94%AE%E6%8C%89%E4%B8%8B/21554
- https://stackoverflow.com/questions/7985991/ios-responding-to-physical-keyboard-events-and-uiinternalevent
- https://stackoverflow.com/questions/7379038/gseventcreatekeyevent

### External HID bridge

Projects such as InputStick and BLE HID keyboard firmware show the cleanest route to real parity: an external device presents as USB/Bluetooth HID, and the host OS treats it as an actual keyboard. For KeyMore, that means a companion hardware bridge is the only currently plausible non-private route to arbitrary-app external-keyboard behavior.

Sources:
- https://github.com/inputstick/InputStickAPI-iOS
- https://github.com/HijelHub/HijelHID_BLEKeyboard

## Sources To Track

- Apple Custom Keyboard documentation: https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard
- Apple App Extension Custom Keyboard guide: https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html
- Apple App Review Guidelines, public API rule: https://developer.apple.com/app-store/review/guidelines/
- Apple responder physical-key APIs: https://developer.apple.com/documentation/uikit/uiresponder/pressesbegan(_:with:)
- Private/prior-art leads: GraphicsServices/GSEvent, BackBoardServices/BKSHID, WebDriverAgent/Appium XCTest synthesis, IOKit HID keyboard events, BLE/USB HID bridge examples.
