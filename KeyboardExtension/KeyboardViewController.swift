import KeyMoreCore
import UIKit
import os

final class KeyboardViewController: UIInputViewController {
    private static let keyboardHeight: CGFloat = 300

    private let logger = Logger(subsystem: "com.rudironsoni.KeyMore.Keyboard", category: "Keyboard")
    private let stackView = UIStackView()
    private var heightConstraint: NSLayoutConstraint?
    private var inputContext = KeyboardInputContext()
    private var modifierButtons: [SpecialKey: UIButton] = [:]
    private var characterButtons: [UIButton: String] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        configureKeyboard()
    }

    private func configureKeyboard() {
        if heightConstraint == nil {
            let constraint = view.heightAnchor.constraint(equalToConstant: Self.keyboardHeight)
            constraint.priority = .required
            constraint.isActive = true
            heightConstraint = constraint
        }

        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6)
        ])

        stackView.addArrangedSubview(makeSpecialRow())
        stackView.addArrangedSubview(makeCharacterRow("qwertyuiop"))
        stackView.addArrangedSubview(makeCharacterRow("asdfghjkl"))
        stackView.addArrangedSubview(makeShiftRow())
        stackView.addArrangedSubview(makeBottomRow())
    }

    private func makeSpecialRow() -> UIStackView {
        let row = makeRow()
        for key in [SpecialKey.escape, .control, .option, .command, .tab] {
            let button = makeButton(title: key.displayTitle)
            button.addAction(UIAction { [weak self] _ in self?.handleSpecialKey(key) }, for: .touchUpInside)
            row.addArrangedSubview(button)

            if [.control, .option, .command].contains(key) {
                modifierButtons[key] = button
            }
        }
        return row
    }

    private func makeCharacterRow(_ characters: String) -> UIStackView {
        let row = makeRow()
        for character in characters.map(String.init) {
            let button = makeButton(title: displayCharacter(character))
            characterButtons[button] = character
            button.addAction(UIAction { [weak self] _ in self?.handleCharacter(character) }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        return row
    }

    private func makeShiftRow() -> UIStackView {
        let row = makeRow()
        let shift = makeButton(title: "shift", symbolName: "shift.fill", weight: 1.35)
        shift.addAction(UIAction { [weak self] _ in self?.toggleShift() }, for: .touchUpInside)
        row.addArrangedSubview(shift)

        for character in "zxcvbnm".map(String.init) {
            let button = makeButton(title: displayCharacter(character))
            characterButtons[button] = character
            button.addAction(UIAction { [weak self] _ in self?.handleCharacter(character) }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }

        let delete = makeButton(title: "delete", symbolName: "delete.left", weight: 1.35)
        delete.addAction(UIAction { [weak self] _ in self?.handleInput(.delete) }, for: .touchUpInside)
        row.addArrangedSubview(delete)
        return row
    }

    private func makeBottomRow() -> UIStackView {
        let row = makeRow()

        let globe = makeButton(title: "next", symbolName: "globe", weight: 1.15)
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        row.addArrangedSubview(globe)

        let space = makeButton(title: "space", weight: 2.4)
        space.addAction(UIAction { [weak self] _ in self?.handleInput(.space) }, for: .touchUpInside)
        row.addArrangedSubview(space)

        let enter = makeButton(title: "return", symbolName: "return", weight: 1.35)
        enter.addAction(UIAction { [weak self] _ in self?.handleInput(.return) }, for: .touchUpInside)
        row.addArrangedSubview(enter)

        return row
    }

    private func handleSpecialKey(_ key: SpecialKey) {
        logger.info("special key press key=\(key.displayTitle, privacy: .public) fullAccess=\(self.hasFullAccess, privacy: .public)")
        handleInput(.special(key))
    }

    private func handleCharacter(_ rawCharacter: String) {
        let character = displayCharacter(rawCharacter)
        logger.info("character key press key=\(character, privacy: .public) fullAccess=\(self.hasFullAccess, privacy: .public)")
        handleInput(.character(rawCharacter))
    }

    private func handleInput(_ input: KeyboardInput) {
        let result = KeyboardInputMethod.resolve(input, context: inputContext)
        inputContext = result.nextContext

        for outputEvent in result.outputEvents {
            apply(outputEvent)
        }

        if result.shouldRebuildCharacterLabels {
            rebuildCharacterLabels()
        }

        if result.shouldUpdateModifierButtons {
            updateModifierButtons()
        }
    }

    private func apply(_ outputEvent: KeyboardOutputEvent) {
        switch outputEvent {
        case .keyPress(let keyLabel, let keyPress, let fallback):
            emitKeyPress(keyLabel: keyLabel, keyPress: keyPress, fallback: fallback)
        case .modifierState(let keyLabel, let report):
            sendModifierState(keyLabel: keyLabel, report: report)
        case .textInput(let resolution):
            apply(resolution)
        }
    }

    private func apply(_ resolution: KeyResolution) {
        switch resolution.action {
        case .insertText(let text):
            textDocumentProxy.insertText(text)
        case .deleteBackward:
            textDocumentProxy.deleteBackward()
        case .noOperation:
            break
        }
    }

    private func toggleShift() {
        handleInput(.shift)
    }

    private func rebuildCharacterLabels() {
        for (button, character) in characterButtons {
            button.setTitle(displayCharacter(character), for: .normal)
        }
    }

    private func updateModifierButtons() {
        for (key, button) in modifierButtons {
            button.isSelected = inputContext.activeModifiers.contains(key)
            button.backgroundColor = button.isSelected ? .systemBlue : .secondarySystemBackground
            button.setTitleColor(button.isSelected ? .white : .label, for: .normal)
        }
    }

    private func displayCharacter(_ character: String) -> String {
        inputContext.isShifted ? character.uppercased() : character.lowercased()
    }

    private func makeRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 4
        row.distribution = .fillProportionally
        row.alignment = .fill
        return row
    }

    private func makeButton(title: String, symbolName: String? = nil, weight: CGFloat = 1) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        if let symbolName {
            configuration.image = UIImage(systemName: symbolName)
            configuration.title = nil
        }
        configuration.baseBackgroundColor = .secondarySystemBackground
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)

        let button = KeyboardKeyButton(weight: weight, configuration: configuration)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.58
        button.titleLabel?.lineBreakMode = .byClipping
        button.titleLabel?.numberOfLines = 1
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        button.accessibilityLabel = title
        return button
    }

    private func emitKeyPress(keyLabel: String, keyPress: HIDKeyPress?, fallback: KeyResolution) {
        guard let keyPress else {
            apply(fallback)
            return
        }

        let message = HIDBridgeMessage.keyPress(
            keyLabel: keyLabel,
            keyPress: keyPress,
            fallbackAction: fallback.action.diagnosticDescription
        )
        sendBridgeMessage(message)
        VirtualHIDKeyboardDispatcher.shared.dispatch(message) { [weak self] result in
            self?.logger.info("virtual HID key=\(keyLabel, privacy: .public) outcome=\(result.outcome.rawValue, privacy: .public) detail=\(result.detail, privacy: .public)")
            guard result.shouldApplyTextProxyFallback else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.apply(fallback)
            }
        }
    }

    private func sendModifierState(keyLabel: String, report: HIDKeyboardReport) {
        let message = HIDBridgeMessage.modifierState(keyLabel: keyLabel, report: report)
        sendBridgeMessage(message)
        VirtualHIDKeyboardDispatcher.shared.dispatch(message) { [weak self] result in
            self?.logger.info("virtual HID modifier=\(keyLabel, privacy: .public) outcome=\(result.outcome.rawValue, privacy: .public) detail=\(result.detail, privacy: .public)")
        }
    }

    private func sendBridgeMessage(_ message: HIDBridgeMessage) {
        HIDBridgeClient.shared.send(message)
    }
}

private final class KeyboardKeyButton: UIButton {
    private let keyWeight: CGFloat

    init(weight: CGFloat, configuration: UIButton.Configuration) {
        self.keyWeight = weight
        super.init(frame: .zero)
        self.configuration = configuration
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 44 * keyWeight, height: 40)
    }
}
