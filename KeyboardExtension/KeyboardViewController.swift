import KeyboardExtensionKit
import KeyMoreCore
import SwiftUI
import UIKit
import os

private enum KeyboardMetrics {
    static let keyboardHeight: CGFloat = 312
    static let outerInset: CGFloat = 3
    static let topInset: CGFloat = 6
    static let bottomInset: CGFloat = 6
    static let rowSpacing: CGFloat = 7
    static let keySpacing: CGFloat = 6
    static let baseKeyWidth: CGFloat = 34
    static let keyHeight: CGFloat = 43
    static let keyCornerRadius: CGFloat = 5
}

private enum KeyboardKeyStyle {
    case character
    case action
    case modifier
    case space

    var font: Font {
        switch self {
        case .character:
            return .system(size: 22, weight: .regular)
        case .action, .modifier, .space:
            return .system(size: 16, weight: .regular)
        }
    }

    func backgroundColor(isSelected: Bool) -> Color {
        if isSelected {
            return .keyMoreSelectedKeyBackground
        }

        switch self {
        case .character, .space:
            return .keyMoreCharacterKeyBackground
        case .action, .modifier:
            return .keyMoreActionKeyBackground
        }
    }

    func foregroundColor(isSelected: Bool) -> Color {
        isSelected ? .keyMoreSelectedKeyForeground : .keyMoreKeyForeground
    }
}

private enum KeyboardLayoutMode {
    case alphabetic
    case numeric
    case symbols
}

@MainActor
private final class KeyMoreKeyboardState: ObservableObject {
    @Published var inputContext = KeyboardInputContext()
    @Published var layoutMode = KeyboardLayoutMode.alphabetic
    @Published var languageLayout = KeyboardLanguageLayout.layout(for: nil)
    @Published var enabledLanguageLayouts = [KeyboardLanguageLayout.layout(for: "en-US")]
    @Published var candidates: [String] = []
    @Published var needsResetShiftState = false
    @Published var isCapsLocked = false
    @Published var needsInputModeSwitchKey = true
}

private struct KeyMoreKeyboardActions {
    let specialKey: (SpecialKey) -> Void
    let character: (String) -> Void
    let shiftState: (KEShiftState) -> Void
    let delete: () -> Void
    let space: () -> Void
    let returnKey: () -> Void
    let candidate: (Int) -> Void
    let swipe: ([String]) -> Void
    let switchLayout: (KeyboardLayoutMode) -> Void
    let globe: (UIView, UIEvent) -> Void
}

private struct SwipeKeyFrame: Equatable {
    let character: String
    let frame: CGRect
}

private struct SwipeKeyFramePreferenceKey: PreferenceKey {
    static let defaultValue: [SwipeKeyFrame] = []

    static func reduce(value: inout [SwipeKeyFrame], nextValue: () -> [SwipeKeyFrame]) {
        value.append(contentsOf: nextValue())
    }
}

final class KeyboardViewController: UIInputViewController {
    private let logger = Logger(subsystem: "com.rudironsoni.KeyMore.Keyboard", category: "Keyboard")
    private let keyboardState = KeyMoreKeyboardState()
    private var heightConstraint: NSLayoutConstraint?
    private var hostingController: UIHostingController<KeyMoreKeyboardView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureKeyboard()
        syncLanguageAndTextBehavior()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        keyboardState.needsInputModeSwitchKey = needsInputModeSwitchKey
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        syncLanguageAndTextBehavior()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        syncLanguageAndTextBehavior()
    }

    private func configureKeyboard() {
        if heightConstraint == nil {
            let constraint = view.heightAnchor.constraint(equalToConstant: KeyboardMetrics.keyboardHeight)
            constraint.priority = .required
            constraint.isActive = true
            heightConstraint = constraint
        }

        view.backgroundColor = .keyMoreKeyboardBackground

        let keyboardView = KeyMoreKeyboardView(
            state: keyboardState,
            actions: KeyMoreKeyboardActions(
                specialKey: { [weak self] in self?.handleSpecialKey($0) },
                character: { [weak self] in self?.handleCharacter($0) },
                shiftState: { [weak self] in self?.handleShiftState($0) },
                delete: { [weak self] in self?.handleInput(.delete) },
                space: { [weak self] in self?.handleSpace() },
                returnKey: { [weak self] in self?.handleInput(.return) },
                candidate: { [weak self] in self?.handleCandidateSelection($0) },
                swipe: { [weak self] in self?.handleSwipe($0) },
                switchLayout: { [weak self] in self?.switchLayout(to: $0) },
                globe: { [weak self] from, event in self?.handleInputModeList(from: from, with: event) }
            )
        )
        let hostingController = UIHostingController(rootView: keyboardView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func handleSpecialKey(_ key: SpecialKey) {
        logger.info("special key press key=\(key.displayTitle, privacy: .public) fullAccess=\(self.hasFullAccess, privacy: .public)")
        handleInput(.special(key))
    }

    private func handleCharacter(_ rawCharacter: String) {
        let character = displayCharacter(rawCharacter)
        logger.info("character key press key=\(character, privacy: .public) fullAccess=\(self.hasFullAccess, privacy: .public)")
        handleInput(.character(rawCharacter))
        resetOneShotShiftIfNeeded()
    }

    private func handleSpace() {
        guard keyboardState.inputContext.activeModifiers.isEmpty,
              KeyboardTextBehavior.shouldInsertPeriodOnDoubleSpace(
                documentContextBeforeInput: textDocumentProxy.documentContextBeforeInput
              ) else {
            handleInput(.space)
            return
        }

        textDocumentProxy.deleteBackward()
        textDocumentProxy.insertText(". ")
        syncLanguageAndTextBehavior()
    }

    private func handleSwipe(_ path: [String]) {
        guard keyboardState.layoutMode == .alphabetic,
              keyboardState.inputContext.activeModifiers.isEmpty,
              let resolution = KeyboardSwipeResolver.resolve(
                path: path,
                languageIdentifier: keyboardState.languageLayout.languageIdentifier,
                documentContextBeforeInput: textDocumentProxy.documentContextBeforeInput
              ) else {
            return
        }

        logger.info("swipe path=\(path.joined(separator: ">"), privacy: .public) text=\(resolution.text, privacy: .public) dictionary=\(resolution.isDictionaryMatch, privacy: .public)")
        textDocumentProxy.insertText(resolution.text)
        keyboardState.candidates = swipeCandidates(for: resolution)
        syncLanguageAndTextBehavior()
    }

    private func handleInput(_ input: KeyboardInput) {
        let result = KeyboardInputMethod.resolve(input, context: keyboardState.inputContext)
        keyboardState.inputContext = result.nextContext

        for outputEvent in result.outputEvents {
            apply(outputEvent)
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
            syncLanguageAndTextBehavior()
        case .deleteBackward:
            textDocumentProxy.deleteBackward()
            syncLanguageAndTextBehavior()
        case .noOperation:
            break
        }
    }

    private func handleShiftState(_ shiftState: KEShiftState) {
        var context = keyboardState.inputContext
        context.isShifted = shiftState != .off
        keyboardState.inputContext = context
        keyboardState.isCapsLocked = shiftState == .capsLock
    }

    private func switchLayout(to mode: KeyboardLayoutMode) {
        keyboardState.layoutMode = mode
        var context = keyboardState.inputContext
        context.isShifted = false
        keyboardState.inputContext = context
    }

    private func handleCandidateSelection(_ index: Int) {
        guard keyboardState.candidates.indices.contains(index) else {
            return
        }

        let candidate = keyboardState.candidates[index]
        if let languageLayout = keyboardState.enabledLanguageLayouts.first(where: { $0.languageSwitchTitle == candidate }) {
            keyboardState.languageLayout = languageLayout
            keyboardState.layoutMode = .alphabetic
            updateCandidates()
            syncLanguageAndTextBehavior()
            return
        }

        textDocumentProxy.insertText(candidate.hasSuffix(" ") ? candidate : candidate + " ")
        syncLanguageAndTextBehavior()
    }

    private func syncLanguageAndTextBehavior() {
        let enabledLayouts = KeyboardLanguageLayout.enabledLayouts(
            primaryLanguage: textDocumentProxy.documentInputMode?.primaryLanguage ?? primaryLanguage,
            preferredLanguages: Locale.preferredLanguages
        )
        if enabledLayouts != keyboardState.enabledLanguageLayouts {
            keyboardState.enabledLanguageLayouts = enabledLayouts
            updateCandidates()
        }
        if !enabledLayouts.contains(where: { $0.languageCode == keyboardState.languageLayout.languageCode }),
           let firstLayout = enabledLayouts.first {
            keyboardState.languageLayout = firstLayout
            updateCandidates()
        }

        guard keyboardState.layoutMode == .alphabetic else {
            return
        }

        let shouldShift = KeyboardTextBehavior.shouldAutoCapitalize(
            documentContextBeforeInput: textDocumentProxy.documentContextBeforeInput
        )
        guard keyboardState.inputContext.isShifted != shouldShift else {
            return
        }

        var context = keyboardState.inputContext
        context.isShifted = shouldShift
        keyboardState.inputContext = context
    }

    private func resetOneShotShiftIfNeeded() {
        guard !keyboardState.isCapsLocked, keyboardState.inputContext.isShifted else {
            return
        }

        var context = keyboardState.inputContext
        context.isShifted = false
        keyboardState.inputContext = context
        keyboardState.needsResetShiftState = true
    }

    private func updateCandidates() {
        keyboardState.candidates = keyboardState.enabledLanguageLayouts.map(\.languageSwitchTitle)
    }

    private func swipeCandidates(for resolution: KeyboardSwipeResolution) -> [String] {
        let languageCandidates = keyboardState.enabledLanguageLayouts.map(\.languageSwitchTitle)
        let word = resolution.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else {
            return languageCandidates
        }
        return [word] + languageCandidates
    }

    private func displayCharacter(_ character: String) -> String {
        keyboardState.inputContext.isShifted ? character.uppercased() : character.lowercased()
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

private struct KeyMoreKeyboardView: View {
    @ObservedObject var state: KeyMoreKeyboardState
    let actions: KeyMoreKeyboardActions
    @State private var swipeKeyFrames: [SwipeKeyFrame] = []
    @State private var swipePath: [String] = []

    var body: some View {
        VStack(spacing: KeyboardMetrics.rowSpacing) {
            candidatesView
            specialRow
            switch state.layoutMode {
            case .alphabetic:
                characterRow(state.languageLayout.alphabeticRows[0])
                characterRow(state.languageLayout.alphabeticRows[1], horizontalInset: 18)
                shiftRow(state.languageLayout.alphabeticRows[2])
                alphabeticBottomRow
            case .numeric:
                characterRow(state.languageLayout.numericRows[0])
                characterRow(state.languageLayout.numericRows[1])
                alternateShiftRow(toggleTitle: "#+=", targetMode: .symbols)
                alternateBottomRow(modeTitle: "ABC", targetMode: .alphabetic)
            case .symbols:
                characterRow(state.languageLayout.symbolRows[0])
                characterRow(state.languageLayout.symbolRows[1])
                alternateShiftRow(toggleTitle: "123", targetMode: .numeric)
                alternateBottomRow(modeTitle: "ABC", targetMode: .alphabetic)
            }
        }
        .padding(.top, KeyboardMetrics.topInset)
        .padding(.leading, KeyboardMetrics.outerInset)
        .padding(.trailing, KeyboardMetrics.outerInset)
        .padding(.bottom, KeyboardMetrics.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.keyMoreKeyboardBackground)
        .coordinateSpace(name: "keyboard")
        .onPreferenceChange(SwipeKeyFramePreferenceKey.self) { frames in
            swipeKeyFrames = frames
        }
        .simultaneousGesture(swipeGesture)
    }

    private var candidatesView: some View {
        KECandidatesView(
            candidates: Binding(
                get: { state.candidates },
                set: { state.candidates = $0 }
            ),
            onSelectHandler: actions.candidate
        )
        .background(Color.keyMoreKeyboardBackground)
    }

    private var specialRow: some View {
        row {
            ForEach(SpecialKey.allCases, id: \.id) { key in
                keyButton(
                    title: key.displayTitle,
                    style: .modifier,
                    isSelected: state.inputContext.activeModifiers.contains(key)
                ) {
                    actions.specialKey(key)
                }
            }
        }
    }

    private func characterRow(_ characters: [String], horizontalInset: CGFloat = 0) -> some View {
        row(horizontalInset: horizontalInset) {
            ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                characterKeyButton(character)
            }
        }
    }

    private func shiftRow(_ characters: [String]) -> some View {
        row {
            shiftButton
            ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                characterKeyButton(character)
            }
            repeatableCommandButton(symbolName: "delete.left", weight: 1.45) {
                actions.delete()
            }
        }
    }

    private var shiftButton: some View {
        KEShiftButton(
            width: KeyboardMetrics.baseKeyWidth * 1.45,
            height: KeyboardMetrics.keyHeight,
            cornerRadius: KeyboardMetrics.keyCornerRadius,
            foregroundInactiveColor: KeyboardKeyStyle.action.foregroundColor(isSelected: state.inputContext.isShifted),
            foregroundActiveColor: KeyboardKeyStyle.action.foregroundColor(isSelected: true),
            backgroundInactiveColor: KeyboardKeyStyle.action.backgroundColor(isSelected: state.inputContext.isShifted),
            backgroundActiveColor: KeyboardKeyStyle.action.backgroundColor(isSelected: true),
            needsResetShiftState: Binding(
                get: { state.needsResetShiftState },
                set: { state.needsResetShiftState = $0 }
            ),
            model: KEShiftButtonModel(updateShiftStateHandler: actions.shiftState)
        )
        .font(.system(size: 18, weight: .regular))
        .shadow(color: .keyMoreKeyShadow, radius: 0, x: 0, y: 1)
        .accessibilityLabel("shift")
    }

    private func alternateShiftRow(toggleTitle: String, targetMode: KeyboardLayoutMode) -> some View {
        row {
            keyButton(title: toggleTitle, style: .action, weight: 1.45) {
                actions.switchLayout(targetMode)
            }
            ForEach(Array(state.languageLayout.punctuationRow.enumerated()), id: \.offset) { _, character in
                characterKeyButton(character)
            }
            repeatableCommandButton(symbolName: "delete.left", weight: 1.45) {
                actions.delete()
            }
        }
    }

    private var alphabeticBottomRow: some View {
        row {
            keyButton(title: "123", style: .action, weight: 1.2) {
                actions.switchLayout(.numeric)
            }
            globeButton
            keyButton(title: state.languageLayout.spaceTitle, style: .space, weight: 5.2) {
                actions.space()
            }
            keyButton(title: "return", style: .action, weight: 2.05) {
                actions.returnKey()
            }
        }
    }

    private func alternateBottomRow(modeTitle: String, targetMode: KeyboardLayoutMode) -> some View {
        row {
            keyButton(title: modeTitle, style: .action, weight: 1.2) {
                actions.switchLayout(targetMode)
            }
            globeButton
            keyButton(title: state.languageLayout.spaceTitle, style: .space, weight: 5.2) {
                actions.space()
            }
            keyButton(title: "return", style: .action, weight: 2.05) {
                actions.returnKey()
            }
        }
    }

    private var globeButton: some View {
        KEGlobeButton(
            width: KeyboardMetrics.baseKeyWidth * 1.18,
            height: KeyboardMetrics.keyHeight,
            cornerRadius: KeyboardMetrics.keyCornerRadius,
            foregroundColor: KeyboardKeyStyle.action.foregroundColor(isSelected: false),
            backgroundInactiveColor: KeyboardKeyStyle.action.backgroundColor(isSelected: false),
            backgroundActiveColor: .keyMorePressedKeyBackground,
            onGlobeHandler: actions.globe
        )
        .opacity(state.needsInputModeSwitchKey ? 1 : 0.55)
        .shadow(color: .keyMoreKeyShadow, radius: 0, x: 0, y: 1)
        .accessibilityLabel("next")
    }

    private func row<Content: View>(
        horizontalInset: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: KeyboardMetrics.keySpacing, content: content)
            .padding(.horizontal, horizontalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.layoutDirection, state.languageLayout.prefersRightToLeft ? .rightToLeft : .leftToRight)
    }

    private func keyButton(
        title: String,
        style: KeyboardKeyStyle,
        weight: CGFloat = 1,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        KEKeyButton(
            text: title,
            width: nil,
            height: KeyboardMetrics.keyHeight,
            maxWidth: .infinity,
            cornerRadius: KeyboardMetrics.keyCornerRadius,
            foregroundColor: style.foregroundColor(isSelected: isSelected),
            backgroundInactiveColor: style.backgroundColor(isSelected: isSelected),
            backgroundActiveColor: .keyMorePressedKeyBackground,
            onKeyHandler: action
        )
        .font(style.font)
        .lineLimit(1)
        .minimumScaleFactor(0.62)
        .frame(width: fixedWidth(for: weight))
        .shadow(color: .keyMoreKeyShadow, radius: 0, x: 0, y: 1)
        .accessibilityLabel(title)
    }

    private func characterKeyButton(_ character: String) -> some View {
        keyButton(title: displayCharacter(character), style: .character) {
            actions.character(character)
        }
        .background(swipeFramePreference(for: character))
    }

    private func swipeFramePreference(for character: String) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: SwipeKeyFramePreferenceKey.self,
                value: [SwipeKeyFrame(character: character.lowercased(), frame: proxy.frame(in: .named("keyboard")))]
            )
        }
    }

    private func commandButton(
        symbolName: String,
        weight: CGFloat,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        KECommandButton(
            image: Image(systemName: symbolName),
            width: KeyboardMetrics.baseKeyWidth * weight,
            height: KeyboardMetrics.keyHeight,
            cornerRadius: KeyboardMetrics.keyCornerRadius,
            foregroundColor: KeyboardKeyStyle.action.foregroundColor(isSelected: isSelected),
            backgroundInactiveColor: KeyboardKeyStyle.action.backgroundColor(isSelected: isSelected),
            backgroundActiveColor: .keyMorePressedKeyBackground,
            onCommandHandler: action
        )
        .font(.system(size: 18, weight: .regular))
        .shadow(color: .keyMoreKeyShadow, radius: 0, x: 0, y: 1)
        .accessibilityLabel(symbolName)
    }

    private func repeatableCommandButton(
        symbolName: String,
        weight: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        KERepeatableCommandButton(
            image: Image(systemName: symbolName),
            width: KeyboardMetrics.baseKeyWidth * weight,
            height: KeyboardMetrics.keyHeight,
            cornerRadius: KeyboardMetrics.keyCornerRadius,
            foregroundColor: KeyboardKeyStyle.action.foregroundColor(isSelected: false),
            backgroundInactiveColor: KeyboardKeyStyle.action.backgroundColor(isSelected: false),
            backgroundActiveColor: .keyMorePressedKeyBackground,
            model: KERepeatableCommandButtonModel(onCommandHandler: action)
        )
        .font(.system(size: 18, weight: .regular))
        .shadow(color: .keyMoreKeyShadow, radius: 0, x: 0, y: 1)
        .accessibilityLabel(symbolName)
    }

    private func fixedWidth(for weight: CGFloat) -> CGFloat? {
        weight == 1 ? nil : KeyboardMetrics.baseKeyWidth * weight
    }

    private func displayCharacter(_ character: String) -> String {
        state.inputContext.isShifted ? character.uppercased() : character.lowercased()
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("keyboard"))
            .onChanged { value in
                appendSwipeKey(at: value.location)
            }
            .onEnded { _ in
                finishSwipe()
            }
    }

    private func appendSwipeKey(at location: CGPoint) {
        guard state.layoutMode == .alphabetic,
              let character = swipeCharacter(at: location),
              swipePath.last != character else {
            return
        }
        swipePath.append(character)
    }

    private func finishSwipe() {
        defer { swipePath.removeAll() }
        guard state.layoutMode == .alphabetic, swipePath.count >= 2 else {
            return
        }
        actions.swipe(swipePath)
    }

    private func swipeCharacter(at location: CGPoint) -> String? {
        if let containingFrame = swipeKeyFrames.first(where: { $0.frame.contains(location) }) {
            return containingFrame.character
        }

        return swipeKeyFrames
            .map { frame in
                (character: frame.character, distance: frame.frame.centerDistance(to: location))
            }
            .filter { $0.distance <= 28 }
            .min { $0.distance < $1.distance }?
            .character
    }
}

private extension CGRect {
    func centerDistance(to point: CGPoint) -> CGFloat {
        let center = CGPoint(x: midX, y: midY)
        return hypot(center.x - point.x, center.y - point.y)
    }
}

private extension UIColor {
    static let keyMoreKeyboardBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)
            : UIColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1)
    }
}

private extension Color {
    static let keyMoreKeyboardBackground = Color(UIColor.keyMoreKeyboardBackground)
    static let keyMoreCharacterKeyBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.39, green: 0.39, blue: 0.41, alpha: 1)
            : .white
    })
    static let keyMoreActionKeyBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1)
            : UIColor(red: 0.67, green: 0.70, blue: 0.75, alpha: 1)
    })
    static let keyMoreSelectedKeyBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.61, green: 0.61, blue: 0.64, alpha: 1)
            : .white
    })
    static let keyMorePressedKeyBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.50, green: 0.50, blue: 0.53, alpha: 1)
            : UIColor(red: 0.78, green: 0.80, blue: 0.84, alpha: 1)
    })
    static let keyMoreKeyForeground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : .black
    })
    static let keyMoreSelectedKeyForeground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : .black
    })
    static let keyMoreKeyShadow = Color.black.opacity(0.30)
}
