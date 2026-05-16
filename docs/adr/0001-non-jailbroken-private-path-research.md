# ADR 0001: Research Non-Jailbroken Private Paths Before Product UI Completion

## Status
Accepted

## Context
KeyMore's product goal is an iOS keyboard with Tab, Esc, Control, Option, and Command keys that behave like a macOS or external iOS/iPadOS hardware keyboard. Public custom keyboard APIs expose text-document operations, not arbitrary hardware keyboard event delivery into other apps.

## Decision
KeyMore will first build a non-jailbroken internal feasibility harness. The harness will compare public text-proxy behavior against host-side physical-key diagnostics and private-path probes before treating any special key as implemented.

## Consequences
The first milestone prioritizes evidence over polish. The keyboard UI may expose fallback behavior, but KeyMore will not claim hardware-equivalent modifier support unless host diagnostics observe the same event path as a physical keyboard.

