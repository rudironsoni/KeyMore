# ADR 0002: Pursue CoreHID Virtual Keyboard Entitlement

## Status
Accepted

## Context
KeyMore needs hardware-equivalent Tab, Esc, Control, Option, and Command behavior. Public custom keyboard APIs only provide text-document proxy operations. A real external HID bridge remains viable, but it adds hardware.

Apple's CoreHID `HIDVirtualDevice` API can model a virtual keyboard and dispatch HID input reports, but virtual HID creation requires the restricted `com.apple.developer.hid.virtual.device` entitlement.

## Decision
KeyMore will implement CoreHID virtual-keyboard dispatch as an experimental parity route. The keyboard extension will attempt to dispatch HID reports through CoreHID first, then fall back to text-proxy behavior when CoreHID is unavailable, unsupported by the OS, or entitlement-blocked.

## Consequences
This gives KeyMore a concrete software route to test and to justify in an Apple entitlement request. It does not remove the need for device proof, App Review review, or a fallback route. If Apple does not grant the entitlement for this use case, the external HID bridge remains the only non-private arbitrary-app route.
