import KeyMoreCore
import UIKit

final class DiagnosticsViewController: UIViewController, UITextViewDelegate {
    private let inputViewField = UITextView()
    private let logView = UITextView()
    private let matrixStack = UIStackView()
    private let bridgeStatusLabel = UILabel()
    private let diagnostics = DiagnosticLog()
    private lazy var hidBridgeServer = HIDBridgeServer { [weak self] status in
        DispatchQueue.main.async {
            self?.bridgeStatusLabel.text = status
            self?.appendLog(status)
            print(status)
        }
    } onMessage: { [weak self] message, ack in
        DispatchQueue.main.async {
            self?.recordBridgeMessage(message, ack: ack)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "KeyMore Diagnostics"
        view.backgroundColor = .systemBackground
        configureLayout()
        renderMatrix()
        appendLog("Focus the field, select KeyMore, then test special keys and an external keyboard.")
        hidBridgeServer.start()
        runPrivatePathProbe()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        DispatchQueue.main.async { [weak self] in
            self?.inputViewField.becomeFirstResponder()
        }
    }

    deinit {
        hidBridgeServer.stop()
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            makeKeyCommand(input: "\t", modifierFlags: [], title: "Tab"),
            makeKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], title: "Escape"),
            makeKeyCommand(input: "c", modifierFlags: [.command], title: "Command-C"),
            makeKeyCommand(input: "v", modifierFlags: [.command], title: "Command-V"),
            makeKeyCommand(input: "a", modifierFlags: [.command], title: "Command-A"),
            makeKeyCommand(input: "c", modifierFlags: [.control], title: "Control-C"),
            makeKeyCommand(input: "d", modifierFlags: [.control], title: "Control-D")
        ]
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        logPresses(presses, kind: .pressBegan)
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        logPresses(presses, kind: .pressEnded)
        super.pressesEnded(presses, with: event)
    }

    @objc private func handleKeyCommand(_ command: UIKeyCommand) {
        let summary = "keyCommand input=\(command.input ?? "nil") modifiers=\(command.modifierFlags.readableDescription)"
        diagnostics.append(DiagnosticEvent(kind: .keyCommand, summary: summary, outcome: .hardwareEquivalent))
        appendLog(summary)
    }

    private func makeKeyCommand(
        input: String,
        modifierFlags: UIKeyModifierFlags,
        title: String
    ) -> UIKeyCommand {
        UIKeyCommand(
            title: title,
            image: nil,
            action: #selector(handleKeyCommand(_:)),
            input: input,
            modifierFlags: modifierFlags,
            propertyList: nil,
            alternates: [],
            discoverabilityTitle: title,
            attributes: [],
            state: .off
        )
    }

    private func configureLayout() {
        let scrollView = UIScrollView()
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let instructions = UILabel()
        instructions.text = "This app records host-side physical keyboard events. Text inserted by the keyboard extension is fallback evidence only."
        instructions.font = .preferredFont(forTextStyle: .body)
        instructions.numberOfLines = 0

        inputViewField.font = .preferredFont(forTextStyle: .title3)
        inputViewField.layer.borderColor = UIColor.separator.cgColor
        inputViewField.layer.borderWidth = 1
        inputViewField.layer.cornerRadius = 8
        inputViewField.text = ""
        inputViewField.delegate = self
        inputViewField.accessibilityIdentifier = "diagnostics-input"

        bridgeStatusLabel.font = .preferredFont(forTextStyle: .footnote)
        bridgeStatusLabel.numberOfLines = 0
        bridgeStatusLabel.text = "HID bridge starting"
        bridgeStatusLabel.accessibilityIdentifier = "hid-bridge-status"

        matrixStack.axis = .vertical
        matrixStack.spacing = 8

        logView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        logView.isEditable = false
        logView.layer.borderColor = UIColor.separator.cgColor
        logView.layer.borderWidth = 1
        logView.layer.cornerRadius = 8
        logView.accessibilityIdentifier = "diagnostics-log"

        contentStack.addArrangedSubview(instructions)
        contentStack.addArrangedSubview(inputViewField)
        contentStack.addArrangedSubview(bridgeStatusLabel)
        contentStack.addArrangedSubview(matrixStack)
        contentStack.addArrangedSubview(logView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            inputViewField.heightAnchor.constraint(equalToConstant: 140),
            logView.heightAnchor.constraint(equalToConstant: 240)
        ])
    }

    private func renderMatrix() {
        matrixStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        addSectionTitle("Key feasibility")
        for record in KeyFeasibilityMatrix.baseline {
            let label = UILabel()
            label.font = .preferredFont(forTextStyle: .footnote)
            label.numberOfLines = 0
            label.text = "\(record.key.displayTitle): \(record.currentResult.rawValue) - \(record.publicFallback)"
            matrixStack.addArrangedSubview(label)
        }

        addSectionTitle("Parity routes")
        for route in ParityRouteMatrix.current {
            let label = UILabel()
            label.font = .preferredFont(forTextStyle: .footnote)
            label.numberOfLines = 0
            let arbitrary = route.canTargetArbitraryApps ? "arbitrary apps" : "not arbitrary"
            let entitlement = route.requiresRestrictedEntitlement ? ", restricted entitlement" : ""
            label.text = "\(route.route.title): \(route.expectedOutcome.rawValue) - \(arbitrary)\(entitlement)"
            matrixStack.addArrangedSubview(label)
        }

        addSectionTitle("HID reports")
        let examples: [(String, HIDKeyPress?)] = [
            ("Cmd-C", HIDReportBuilder.keyPress(for: "c", activeModifiers: [.command])),
            ("Ctrl-Opt-Tab", HIDReportBuilder.keyPress(for: .tab, activeModifiers: [.control, .option])),
            ("Esc", HIDReportBuilder.keyPress(for: .escape))
        ]
        for (title, keyPress) in examples {
            let label = UILabel()
            label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            label.numberOfLines = 0
            label.text = "\(title): \(keyPress?.down.bytes.hexBytes ?? "unavailable")"
            matrixStack.addArrangedSubview(label)
        }
    }

    private func runPrivatePathProbe() {
        for result in PrivatePathProbe.inspect() {
            let summary = "\(result.candidate.displayName): \(result.outcome.rawValue) - \(result.detail)"
            diagnostics.append(DiagnosticEvent(kind: .privatePathProbe, summary: summary, outcome: result.outcome))
            appendLog(summary)
        }
    }

    private func recordBridgeMessage(_ message: HIDBridgeMessage, ack: HIDBridgeAck) {
        let frames = message.frames.map { frame in
            "\(frame.phase.rawValue)=\((frame.bytes).hexBytes)"
        }.joined(separator: " ")
        let summary = "bridge \(message.keyLabel): \(frames) -> \(ack.outcome.rawValue) \(ack.mode.rawValue)"
        bridgeStatusLabel.text = summary
        diagnostics.append(DiagnosticEvent(kind: .hidBridge, summary: summary, outcome: ack.outcome))
        appendLog(summary)
        print(summary)
    }

    private func addSectionTitle(_ title: String) {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.numberOfLines = 0
        label.text = title
        matrixStack.addArrangedSubview(label)
    }

    private func logPresses(_ presses: Set<UIPress>, kind: DiagnosticEventKind) {
        for press in presses {
            guard let key = press.key else {
                appendLog("\(kind.rawValue): non-key press type=\(press.type.rawValue)")
                continue
            }

            let summary = "\(kind.rawValue): keyCode=\(key.keyCode.rawValue) chars=\(key.characters) ignoring=\(key.charactersIgnoringModifiers) modifiers=\(key.modifierFlags.readableDescription)"
            diagnostics.append(DiagnosticEvent(kind: kind, summary: summary, outcome: .hardwareEquivalent))
            appendLog(summary)
        }
    }

    private func appendLog(_ line: String) {
        let text = logView.text ?? ""
        logView.text = text.isEmpty ? line : text + "\n" + line
        let bottom = NSRange(location: max(logView.text.count - 1, 0), length: 1)
        logView.scrollRangeToVisible(bottom)
    }
}

private extension Array where Element == UInt8 {
    var hexBytes: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

private extension UIKeyModifierFlags {
    var readableDescription: String {
        var parts: [String] = []
        if contains(.alphaShift) { parts.append("alphaShift") }
        if contains(.shift) { parts.append("shift") }
        if contains(.control) { parts.append("control") }
        if contains(.alternate) { parts.append("option") }
        if contains(.command) { parts.append("command") }
        if contains(.numericPad) { parts.append("numericPad") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }
}
