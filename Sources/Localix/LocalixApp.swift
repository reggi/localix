import AppKit
import ApplicationServices
import AudioToolbox
import AVFoundation
import CoreAudio
import Speech

private struct DictationHistoryEntry: Codable {
    let date: Date
    let wordCount: Int
    let reason: String
    let applicationNames: [String]?
}

private struct FocusedTextTarget {
    let applicationName: String?
    let controlName: String
}

private struct RecordedHoldShortcut {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let title: String
}

private struct HoldShortcutDefinition {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let title: String
    let usesFlagsChanged: Bool
}

private final class ShortcutKeyCapView: NSView {
    let keyCode: UInt16?
    private let label: NSTextField
    private var highlighted = false

    init(title: String, keyCode: UInt16?, width: CGFloat, height: CGFloat = 36, scale: CGFloat = 1) {
        self.keyCode = keyCode
        self.label = NSTextField(labelWithString: title)
        super.init(frame: .zero)

        let edgeKey = keyCode.map { [UInt16(48), 57, 56, 60, 36, 51, 63, 59, 58, 61].contains($0) } ?? false
        let rightAligned = keyCode.map { [UInt16(36), 51, 60].contains($0) } ?? false
        label.alignment = edgeKey ? (rightAligned ? .right : .left) : .center
        let fontSize: CGFloat = title.count == 1 ? 18 : (title.count == 3 && title.contains("\n") ? 15 : 13)
        label.font = .systemFont(ofSize: max(9, fontSize * scale), weight: .regular)
        label.maximumNumberOfLines = 2
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: height),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: edgeKey ? 5 * scale : 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: edgeKey ? -5 * scale : -2),
            edgeKey
                ? label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5 * scale)
                : label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setHighlighted(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setHighlighted(_ highlighted: Bool) {
        self.highlighted = highlighted
        label.textColor = highlighted ? .selectedControlTextColor : .labelColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4
        )
        (highlighted ? NSColor.controlAccentColor : NSColor.controlColor).setFill()
        shape.fill()
        NSColor.separatorColor.setStroke()
        shape.stroke()
    }
}

private final class ShortcutRecorderView: NSView {
    private struct KeySpec {
        let title: String
        let keyCode: UInt16?
        let width: CGFloat

        init(_ title: String, _ keyCode: UInt16?, _ width: CGFloat = 1) {
            self.title = title
            self.keyCode = keyCode
            self.width = width
        }
    }

    private let shortcutLabel = NSTextField(labelWithString: "Type Shortcut")
    private let shortcutKeyCaps = NSStackView()
    private let detailLabel = NSTextField(labelWithString: "")
    private let keyboardStack = NSStackView()
    private let disclosureButton = NSButton(title: "", target: nil, action: nil)
    private let disclosureTitle = NSButton(title: "Show Keyboard", target: nil, action: nil)
    private let recordingField = NSBox()
    private var recorderHeight: NSLayoutConstraint!
    private var disclosureTop: NSLayoutConstraint!
    private var keyCaps: [UInt16: ShortcutKeyCapView] = [:]
    private var pressedModifierKeyCodes: Set<UInt16> = []
    private(set) var recordedShortcut: RecordedHoldShortcut?
    var onChange: ((RecordedHoldShortcut?) -> Void)?
    var onCancel: (() -> Void)?
    var onSave: (() -> Void)?
    var onKeyboardVisibilityChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        shortcutLabel.font = .systemFont(ofSize: 13)
        shortcutLabel.textColor = .placeholderTextColor
        shortcutLabel.alignment = .center
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.isHidden = true
        shortcutKeyCaps.spacing = 4
        shortcutKeyCaps.alignment = .centerY
        shortcutKeyCaps.setHuggingPriority(.required, for: .horizontal)
        shortcutKeyCaps.isHidden = true
        recordingField.boxType = .custom
        recordingField.isTransparent = false
        recordingField.fillColor = .controlBackgroundColor
        recordingField.borderColor = .separatorColor
        recordingField.borderWidth = 1
        recordingField.cornerRadius = 6
        recordingField.setAccessibilityElement(true)
        recordingField.setAccessibilityRole(.textField)
        recordingField.setAccessibilityLabel("Keyboard shortcut")
        recordingField.setAccessibilityValue("Type Shortcut")

        let rows: [[KeySpec]] = [
            [
                KeySpec("esc", 53), KeySpec("", nil, 0.4),
                KeySpec("F1", 122), KeySpec("F2", 120), KeySpec("F3", 99),
                KeySpec("F4", 118), KeySpec("", nil, 0.3),
                KeySpec("F5", 96), KeySpec("F6", 97), KeySpec("F7", 98),
                KeySpec("F8", 100), KeySpec("", nil, 0.3),
                KeySpec("F9", 101), KeySpec("F10", 109), KeySpec("F11", 103),
                KeySpec("F12", 111), KeySpec("⏏", nil)
            ],
            [
                KeySpec("~\n`", 50), KeySpec("!\n1", 18), KeySpec("@\n2", 19), KeySpec("#\n3", 20),
                KeySpec("$\n4", 21), KeySpec("%\n5", 23), KeySpec("^\n6", 22), KeySpec("&\n7", 26),
                KeySpec("*\n8", 28), KeySpec("(\n9", 25), KeySpec(")\n0", 29), KeySpec("_\n-", 27),
                KeySpec("+\n=", 24), KeySpec("delete", 51, 2)
            ],
            [
                KeySpec("tab", 48, 1.6), KeySpec("Q", 12), KeySpec("W", 13), KeySpec("E", 14),
                KeySpec("R", 15), KeySpec("T", 17), KeySpec("Y", 16), KeySpec("U", 32),
                KeySpec("I", 34), KeySpec("O", 31), KeySpec("P", 35), KeySpec("{\n[", 33),
                KeySpec("}\n]", 30), KeySpec("|\n\\", 42, 1.4)
            ],
            [
                KeySpec("caps lock", 57, 1.9), KeySpec("A", 0), KeySpec("S", 1), KeySpec("D", 2),
                KeySpec("F", 3), KeySpec("G", 5), KeySpec("H", 4), KeySpec("J", 38),
                KeySpec("K", 40), KeySpec("L", 37), KeySpec(":\n;", 41), KeySpec("\"\n'", 39),
                KeySpec("return", 36, 2.1)
            ],
            [
                KeySpec("shift", 56, 2.4), KeySpec("Z", 6), KeySpec("X", 7), KeySpec("C", 8),
                KeySpec("V", 9), KeySpec("B", 11), KeySpec("N", 45), KeySpec("M", 46),
                KeySpec("<\n,", 43), KeySpec(">\n.", 47), KeySpec("?\n/", 44), KeySpec("shift", 60, 2.6)
            ],
            [
                KeySpec("fn", 63), KeySpec("⌃", 59, 1.15), KeySpec("⌥", 58, 1.15),
                KeySpec("⌘", 55, 1.5), KeySpec("", 49, 5.5),
                KeySpec("⌘", 54, 1.5), KeySpec("⌥", 61, 1.1)
            ]
        ]

        keyboardStack.orientation = .vertical
        keyboardStack.alignment = .leading
        keyboardStack.spacing = 3

        for (index, row) in rows.enumerated() {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.alignment = .centerY
            rowStack.spacing = 3
            let availableWidth: CGFloat = index == 5 ? 378 : 488
            let unitWidth = (availableWidth - CGFloat(row.count - 1) * 3)
                / row.reduce(0) { $0 + $1.width }
            for spec in row {
                if spec.title.isEmpty, spec.keyCode == nil {
                    let spacer = NSView()
                    spacer.widthAnchor.constraint(equalToConstant: unitWidth * spec.width).isActive = true
                    rowStack.addArrangedSubview(spacer)
                    continue
                }
                let keyCap = ShortcutKeyCapView(
                    title: spec.title,
                    keyCode: spec.keyCode,
                    width: unitWidth * spec.width,
                    height: index == 0 ? 20 : (index == 5 ? 25 : 23),
                    scale: 0.6
                )
                if let keyCode = spec.keyCode {
                    keyCaps[keyCode] = keyCap
                }
                rowStack.addArrangedSubview(keyCap)
            }
            if index == 5 {
                let spacer = NSView()
                spacer.widthAnchor.constraint(equalToConstant: 8).isActive = true
                rowStack.addArrangedSubview(spacer)
                let arrows = NSView()
                arrows.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    arrows.widthAnchor.constraint(equalToConstant: 96),
                    arrows.heightAnchor.constraint(equalToConstant: 25)
                ])
                for (title, code, column, upper) in [
                    ("◀", UInt16(123), 0, false), ("▲", UInt16(126), 1, true),
                    ("▼", UInt16(125), 1, false), ("▶", UInt16(124), 2, false)
                ] {
                    let cap = ShortcutKeyCapView(
                        title: title, keyCode: code, width: 30, height: 12, scale: 0.5
                    )
                    cap.translatesAutoresizingMaskIntoConstraints = false
                    arrows.addSubview(cap)
                    keyCaps[code] = cap
                    NSLayoutConstraint.activate([
                        cap.leadingAnchor.constraint(equalTo: arrows.leadingAnchor, constant: CGFloat(column) * 33),
                        cap.topAnchor.constraint(equalTo: arrows.topAnchor, constant: upper ? 0 : 13)
                    ])
                }
                rowStack.addArrangedSubview(arrows)
            }
            keyboardStack.addArrangedSubview(rowStack)
        }

        keyboardStack.isHidden = true
        disclosureButton.setButtonType(.pushOnPushOff)
        disclosureButton.bezelStyle = .disclosure
        disclosureButton.setAccessibilityLabel("Show Keyboard")
        disclosureButton.target = self
        disclosureButton.action = #selector(toggleKeyboard)
        disclosureTitle.isBordered = false
        disclosureTitle.font = .systemFont(ofSize: 11)
        disclosureTitle.target = self
        disclosureTitle.action = #selector(toggleKeyboardFromTitle)
        let disclosure = NSStackView(views: [disclosureButton, disclosureTitle])
        disclosure.spacing = 2
        disclosure.alignment = .centerY
        for view in [recordingField, shortcutLabel, shortcutKeyCaps, detailLabel, disclosure, keyboardStack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        recorderHeight = heightAnchor.constraint(equalToConstant: 94)
        disclosureTop = disclosure.topAnchor.constraint(equalTo: recordingField.bottomAnchor, constant: 10)
        NSLayoutConstraint.activate([
            recorderHeight,
            recordingField.topAnchor.constraint(equalTo: topAnchor),
            recordingField.centerXAnchor.constraint(equalTo: centerXAnchor),
            recordingField.widthAnchor.constraint(equalToConstant: 384),
            recordingField.heightAnchor.constraint(equalToConstant: 56),
            shortcutLabel.centerXAnchor.constraint(equalTo: recordingField.centerXAnchor),
            shortcutLabel.centerYAnchor.constraint(equalTo: recordingField.centerYAnchor),
            shortcutLabel.leadingAnchor.constraint(greaterThanOrEqualTo: recordingField.leadingAnchor, constant: 12),
            shortcutLabel.trailingAnchor.constraint(lessThanOrEqualTo: recordingField.trailingAnchor, constant: -12),
            shortcutKeyCaps.centerXAnchor.constraint(equalTo: recordingField.centerXAnchor),
            shortcutKeyCaps.centerYAnchor.constraint(equalTo: recordingField.centerYAnchor),
            shortcutKeyCaps.leadingAnchor.constraint(greaterThanOrEqualTo: recordingField.leadingAnchor, constant: 12),
            shortcutKeyCaps.trailingAnchor.constraint(lessThanOrEqualTo: recordingField.trailingAnchor, constant: -12),
            detailLabel.topAnchor.constraint(equalTo: recordingField.bottomAnchor, constant: 4),
            detailLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            detailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            detailLabel.heightAnchor.constraint(equalToConstant: 18),
            disclosureTop,
            disclosure.leadingAnchor.constraint(equalTo: recordingField.leadingAnchor),
            disclosure.heightAnchor.constraint(equalToConstant: 18),
            disclosureButton.widthAnchor.constraint(equalToConstant: 16),
            disclosureButton.heightAnchor.constraint(equalToConstant: 16),
            keyboardStack.topAnchor.constraint(equalTo: disclosure.bottomAnchor, constant: 10),
            keyboardStack.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    @objc private func toggleKeyboard() {
        let visible = disclosureButton.state == .on
        keyboardStack.isHidden = !visible
        disclosureTitle.title = visible ? "Hide Keyboard" : "Show Keyboard"
        disclosureButton.setAccessibilityLabel(disclosureTitle.title)
        recorderHeight.constant = (visible ? 256 : 94) + (detailLabel.isHidden ? 0 : 20)
        onKeyboardVisibilityChange?(visible)
        window?.makeFirstResponder(self)
    }

    @objc private func toggleKeyboardFromTitle() {
        disclosureButton.state = disclosureButton.state == .on ? .off : .on
        toggleKeyboard()
    }

    private func showValidation(_ message: String?) {
        detailLabel.stringValue = message ?? ""
        detailLabel.isHidden = message == nil
        disclosureTop.constant = message == nil ? 10 : 30
        recorderHeight.constant = (disclosureButton.state == .on ? 256 : 94) + (message == nil ? 0 : 20)
    }

    override func flagsChanged(with event: NSEvent) {
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62, 63]
        guard modifierKeyCodes.contains(event.keyCode),
              let modifier = Self.modifierFlag(for: event.keyCode) else {
            return
        }

        if event.modifierFlags.contains(modifier) {
            if recordedShortcut != nil {
                recordedShortcut = nil
                pressedModifierKeyCodes.removeAll()
                for keyCap in keyCaps.values {
                    keyCap.setHighlighted(false)
                }
                onChange?(nil)
            }
            pressedModifierKeyCodes.insert(event.keyCode)
            keyCaps[event.keyCode]?.setHighlighted(true)
        } else {
            pressedModifierKeyCodes.remove(event.keyCode)
            if recordedShortcut == nil {
                keyCaps[event.keyCode]?.setHighlighted(false)
            }
        }
        if recordedShortcut == nil {
            updateSummary(nil, modifiers: event.modifierFlags)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else {
            return
        }

        let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command, .function])
        if event.keyCode == 53, modifiers.isEmpty {
            onCancel?()
            return
        }
        if event.keyCode == 36, modifiers.isEmpty, recordedShortcut != nil {
            onSave?()
            return
        }
        if event.keyCode == 48, modifiers.isEmpty {
            window?.selectNextKeyView(self)
            return
        }
        guard !modifiers.isEmpty else {
            for keyCap in keyCaps.values {
                keyCap.setHighlighted(false)
            }
            updateSummary(nil)
            showValidation("Include a modifier such as Command, Option, Control, or Shift.")
            recordedShortcut = nil
            onChange?(nil)
            return
        }

        let shortcut = RecordedHoldShortcut(
            keyCode: event.keyCode,
            modifiers: modifiers,
            title: Self.shortcutTitle(for: event, modifiers: modifiers)
        )
        for keyCap in keyCaps.values {
            keyCap.setHighlighted(false)
        }
        let modifierKeyCodes = pressedModifierKeyCodes.isEmpty
            ? Self.defaultModifierKeyCodes(for: modifiers)
            : pressedModifierKeyCodes
        for keyCode in modifierKeyCodes {
            keyCaps[keyCode]?.setHighlighted(true)
        }
        keyCaps[event.keyCode]?.setHighlighted(true)
        updateSummary(shortcut)
        recordedShortcut = shortcut
        onChange?(shortcut)
    }

    func restore(_ shortcut: RecordedHoldShortcut) {
        recordedShortcut = shortcut
        pressedModifierKeyCodes.removeAll()
        for keyCap in keyCaps.values {
            keyCap.setHighlighted(false)
        }
        for keyCode in Self.defaultModifierKeyCodes(for: shortcut.modifiers) {
            keyCaps[keyCode]?.setHighlighted(true)
        }
        keyCaps[shortcut.keyCode]?.setHighlighted(true)
        updateSummary(shortcut)
        onChange?(shortcut)
    }

    private func updateSummary(
        _ shortcut: RecordedHoldShortcut?,
        modifiers heldModifiers: NSEvent.ModifierFlags = []
    ) {
        let modifiers: [(NSEvent.ModifierFlags, String, String)] = [
            (.function, "fn", "Fn"), (.control, "⌃", "Control"), (.option, "⌥", "Option"),
            (.shift, "⇧", "Shift"), (.command, "⌘", "Command")
        ]
        let flags = shortcut?.modifiers ?? heldModifiers
        let activeModifiers = modifiers.filter { flags.contains($0.0) }
        var titles = activeModifiers.map { $0.1 }
        var names = activeModifiers.map { $0.2 }
        if let shortcut {
            var keyTitle = shortcut.title
            for title in titles {
                if keyTitle.hasPrefix(title) {
                    keyTitle.removeFirst(title.count)
                    keyTitle = keyTitle.trimmingCharacters(in: .whitespaces)
                }
            }
            titles.append(keyTitle)
            names.append(keyTitle)
        }
        for view in shortcutKeyCaps.arrangedSubviews {
            shortcutKeyCaps.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for title in titles {
            let width = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
            shortcutKeyCaps.addArrangedSubview(ShortcutKeyCapView(
                title: title, keyCode: nil, width: max(28, ceil(width) + 14), height: 28, scale: 0.85
            ))
        }
        shortcutLabel.isHidden = !titles.isEmpty
        shortcutKeyCaps.isHidden = titles.isEmpty
        showValidation(nil)
        recordingField.setAccessibilityValue(
            names.isEmpty ? "Type Shortcut" : names.joined(separator: ", ")
        )
    }

    private static func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55:
            return .command
        case 56, 60:
            return .shift
        case 58, 61:
            return .option
        case 59, 62:
            return .control
        case 63:
            return .function
        default:
            return nil
        }
    }

    private static func defaultModifierKeyCodes(
        for modifiers: NSEvent.ModifierFlags
    ) -> Set<UInt16> {
        var keyCodes: Set<UInt16> = []
        if modifiers.contains(.function) {
            keyCodes.insert(63)
        }
        if modifiers.contains(.control) {
            keyCodes.insert(59)
        }
        if modifiers.contains(.option) {
            keyCodes.insert(58)
        }
        if modifiers.contains(.shift) {
            keyCodes.insert(56)
        }
        if modifiers.contains(.command) {
            keyCodes.insert(55)
        }
        return keyCodes
    }

    private static func shortcutTitle(
        for event: NSEvent,
        modifiers: NSEvent.ModifierFlags
    ) -> String {
        var title = ""
        if modifiers.contains(.function) {
            title += "fn "
        }
        if modifiers.contains(.control) {
            title += "⌃"
        }
        if modifiers.contains(.option) {
            title += "⌥"
        }
        if modifiers.contains(.shift) {
            title += "⇧"
        }
        if modifiers.contains(.command) {
            title += "⌘"
        }

        let namedKeys: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
            115: "Home", 116: "Page Up", 117: "Forward Delete", 119: "End",
            121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        if let namedKey = namedKeys[event.keyCode] {
            return title + namedKey
        }

        let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if let characters, !characters.isEmpty {
            return title + characters
        }

        return title + "Key \(event.keyCode)"
    }
}

private final class ShortcutRecorderWindowController: NSWindowController, NSWindowDelegate {
    let recorder = ShortcutRecorderView(frame: .zero)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 280),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Record Keyboard Shortcut"
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true

        let background = NSView()
        window.contentView = background

        let title = NSTextField(labelWithString: "Record Keyboard Shortcut")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Press the keyboard shortcut you want to use.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 6

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.isEnabled = false
        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.spacing = 10
        for view in [heading, recorder, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 24),
            heading.topAnchor.constraint(equalTo: background.topAnchor, constant: 20),
            recorder.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            recorder.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            recorder.topAnchor.constraint(equalTo: background.topAnchor, constant: 80),
            buttons.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -24),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: recorder.bottomAnchor, constant: 10),
            buttons.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -20),
            saveButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
        recorder.onChange = { [weak self] shortcut in
            guard let self else { return }
            let valid = shortcut != nil
            self.saveButton.isEnabled = valid
            self.saveButton.keyEquivalent = valid ? "\r" : ""
            self.saveButton.bezelColor = valid ? .controlAccentColor : nil
            self.window?.defaultButtonCell = valid ? self.saveButton.cell as? NSButtonCell : nil
        }
        recorder.onCancel = { [weak self] in self?.cancel() }
        recorder.onSave = { [weak self] in self?.save() }
        recorder.onKeyboardVisibilityChange = { [weak self] visible in
            guard let window = self?.window else { return }
            let size = NSSize(width: 520, height: visible ? 442 : 280)
            let oldFrame = window.frame
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            frame.origin = NSPoint(x: oldFrame.midX - frame.width / 2, y: oldFrame.maxY - frame.height)
            window.setFrame(frame, display: true)
        }
        window.initialFirstResponder = recorder
    }

    required init?(coder: NSCoder) {
        nil
    }

    func runModal() -> NSApplication.ModalResponse {
        guard let window else { return .cancel }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(recorder)
        defer { window.orderOut(nil) }
        return NSApp.runModal(for: window)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel()
        return false
    }

    @objc private func cancel() {
        NSApp.stopModal(withCode: .cancel)
    }

    @objc private func save() {
        guard recorder.recordedShortcut != nil else { return }
        NSApp.stopModal(withCode: .OK)
    }
}

private enum HoldShortcut: String {
    case off
    case rightOption
    case rightShift
    case custom

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .rightOption:
            return "Right Option"
        case .rightShift:
            return "Right Shift"
        case .custom:
            return "Custom"
        }
    }
}

private enum ShortcutBehavior: String, CaseIterable {
    case hold
    case toggle

    var title: String {
        switch self {
        case .hold:
            return "Hold to Record"
        case .toggle:
            return "Press to Start or Stop"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let autoStopMinutesKey = "autoStopMinutes"
    private static let silenceTimeoutMinutesKey = "silenceTimeoutMinutes"
    private static let defaultsVersionKey = "defaultsVersion"
    private static let historyKey = "dictationHistory"
    private static let inputDeviceUIDKey = "inputDeviceUID"
    private static let inputDeviceNameKey = "inputDeviceName"
    private static let holdShortcutKey = "holdShortcut"
    private static let customShortcutKeyCodeKey = "customShortcutKeyCode"
    private static let customShortcutModifiersKey = "customShortcutModifiers"
    private static let customShortcutTitleKey = "customShortcutTitle"
    private static let shortcutBehaviorKey = "shortcutBehavior"

    private let audioEngine = AVAudioEngine()
    private var statusItem: NSStatusItem!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var transcript = ""
    private var deliveredTranscript = ""
    private var recognitionGeneration = 0
    private var isRecording = false
    private var isFinishing = false
    private var sessionText = ""
    private var sessionApplicationNames: [String] = []
    private var sessionStartedAt: Date?
    private var pendingStopReason = "Stopped manually"
    private var autoStopTimer: Timer?
    private var silenceTimer: Timer?
    private var hasStartedSessionTimers = false
    private var globalShortcutMonitor: Any?
    private var localShortcutMonitor: Any?
    private var shortcutIsHeld = false
    private var shortcutOwnsRecording = false
    private var isRecordingCustomShortcut = false
    private weak var activeShortcutRecorder: ShortcutRecorderView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateDefaultsIfNeeded()
        UserDefaults.standard.register(defaults: [
            Self.autoStopMinutesKey: 10,
            Self.silenceTimeoutMinutesKey: 1,
            Self.holdShortcutKey: HoldShortcut.rightOption.rawValue,
            Self.shortcutBehaviorKey: ShortcutBehavior.hold.rawValue
        ])
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Localix runs from the menu bar")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true

        guard let button = statusItem.button else {
            NSLog("Localix could not create its menu bar button")
            return
        }

        button.image = statusImage(
            symbolName: "text.bubble",
            accessibilityDescription: "Start Localix",
            hasRedBackground: false
        )
        button.toolTip = "Localix"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        installHoldShortcutMonitors()
        NSLog("Localix menu bar item created")
    }

    private func migrateDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Self.defaultsVersionKey) < 1 else {
            return
        }

        if defaults.object(forKey: Self.autoStopMinutesKey) == nil
            || defaults.integer(forKey: Self.autoStopMinutesKey) == 30 {
            defaults.set(10, forKey: Self.autoStopMinutesKey)
        }
        if defaults.object(forKey: Self.silenceTimeoutMinutesKey) == nil
            || defaults.integer(forKey: Self.silenceTimeoutMinutesKey) == 5 {
            defaults.set(1, forKey: Self.silenceTimeoutMinutesKey)
        }
        defaults.set(1, forKey: Self.defaultsVersionKey)
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeHoldShortcutMonitors()
        invalidateSessionTimers()
        if sessionStartedAt != nil {
            pendingStopReason = "App quit"
        }
        recordHistoryIfNeeded()
        recognitionGeneration += 1
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        NSLog("Localix released microphone resources")
    }

    @objc
    private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }

        if isRecording {
            finishRecording()
        } else if !isFinishing {
            beginDictation()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let stateTitle: String
        if isRecording {
            stateTitle = "Recording on this Mac"
        } else if isFinishing {
            stateTitle = "Finishing local transcription"
        } else {
            stateTitle = "Ready for local dictation"
        }
        let stateItem = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        let cursorItem = NSMenuItem(
            title: "Types into: \(focusedTextTargetDescription())",
            action: nil,
            keyEquivalent: ""
        )
        cursorItem.isEnabled = false
        menu.addItem(cursorItem)
        addMicrophoneMenu(to: menu)
        addHoldShortcutMenu(to: menu)
        addShortcutBehaviorMenu(to: menu)
        menu.addItem(.separator())
        addHistoryMenu(to: menu)
        addTimeoutMenu(
            to: menu,
            title: "Auto Stop After",
            selectedMinutes: autoStopMinutes,
            action: #selector(setAutoStopMinutes(_:)),
            options: [0, 1, 5, 10, 30, 60]
        )
        addTimeoutMenu(
            to: menu,
            title: "Silence Timeout",
            selectedMinutes: silenceTimeoutMinutes,
            action: #selector(setSilenceTimeoutMinutes(_:)),
            options: [0, 1, 2, 5, 10]
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Localix",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private var autoStopMinutes: Int {
        UserDefaults.standard.integer(forKey: Self.autoStopMinutesKey)
    }

    private var silenceTimeoutMinutes: Int {
        UserDefaults.standard.integer(forKey: Self.silenceTimeoutMinutesKey)
    }

    private var holdShortcut: HoldShortcut {
        let rawValue = UserDefaults.standard.string(forKey: Self.holdShortcutKey)
            ?? HoldShortcut.rightOption.rawValue
        return HoldShortcut(rawValue: rawValue) ?? .rightOption
    }

    private var shortcutBehavior: ShortcutBehavior {
        let rawValue = UserDefaults.standard.string(forKey: Self.shortcutBehaviorKey)
            ?? ShortcutBehavior.hold.rawValue
        return ShortcutBehavior(rawValue: rawValue) ?? .hold
    }

    private var customHoldShortcutDefinition: HoldShortcutDefinition? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.customShortcutKeyCodeKey) != nil,
              let title = defaults.string(forKey: Self.customShortcutTitleKey) else {
            return nil
        }

        let keyCode = UInt16(clamping: defaults.integer(forKey: Self.customShortcutKeyCodeKey))
        let modifiers = NSEvent.ModifierFlags(
            rawValue: UInt(defaults.integer(forKey: Self.customShortcutModifiersKey))
        )
        return HoldShortcutDefinition(
            keyCode: keyCode,
            modifiers: modifiers,
            title: title,
            usesFlagsChanged: false
        )
    }

    private var activeHoldShortcutDefinition: HoldShortcutDefinition? {
        switch holdShortcut {
        case .off:
            return nil
        case .rightOption:
            return HoldShortcutDefinition(
                keyCode: 61,
                modifiers: .option,
                title: "Right Option",
                usesFlagsChanged: true
            )
        case .rightShift:
            return HoldShortcutDefinition(
                keyCode: 60,
                modifiers: .shift,
                title: "Right Shift",
                usesFlagsChanged: true
            )
        case .custom:
            return customHoldShortcutDefinition
        }
    }

    private func addHoldShortcutMenu(to menu: NSMenu) {
        let shortcutItem = NSMenuItem(
            title: "Hold Shortcut: \(activeHoldShortcutDefinition?.title ?? "Off")",
            action: nil,
            keyEquivalent: ""
        )
        let shortcutMenu = NSMenu()

        for shortcut in [HoldShortcut.rightOption, .rightShift] {
            addHoldShortcutItem(shortcut, to: shortcutMenu)
        }

        if customHoldShortcutDefinition != nil {
            addHoldShortcutItem(.custom, to: shortcutMenu)
        }

        let recordItem = NSMenuItem(
            title: customHoldShortcutDefinition == nil
                ? "Record New Shortcut…"
                : "Record Different Shortcut…",
            action: #selector(beginCustomShortcutCapture),
            keyEquivalent: ""
        )
        recordItem.target = self
        recordItem.isEnabled = !isRecording && !isFinishing
        shortcutMenu.addItem(recordItem)
        shortcutMenu.addItem(.separator())
        addHoldShortcutItem(.off, to: shortcutMenu)

        shortcutItem.submenu = shortcutMenu
        menu.addItem(shortcutItem)
    }

    private func addShortcutBehaviorMenu(to menu: NSMenu) {
        let behaviorItem = NSMenuItem(
            title: "Shortcut Behavior: \(shortcutBehavior.title)",
            action: nil,
            keyEquivalent: ""
        )
        let behaviorMenu = NSMenu()

        for behavior in ShortcutBehavior.allCases {
            let item = NSMenuItem(
                title: behavior.title,
                action: #selector(selectShortcutBehavior(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = behavior.rawValue
            item.state = behavior == shortcutBehavior ? .on : .off
            item.isEnabled = !isRecording && !isFinishing
            behaviorMenu.addItem(item)
        }

        behaviorItem.submenu = behaviorMenu
        menu.addItem(behaviorItem)
    }

    @objc
    private func selectShortcutBehavior(_ sender: NSMenuItem) {
        guard !isRecording, !isFinishing,
              let rawValue = sender.representedObject as? String,
              ShortcutBehavior(rawValue: rawValue) != nil else {
            return
        }

        shortcutIsHeld = false
        shortcutOwnsRecording = false
        UserDefaults.standard.set(rawValue, forKey: Self.shortcutBehaviorKey)
    }

    private func addHoldShortcutItem(_ shortcut: HoldShortcut, to menu: NSMenu) {
        let title: String
        if shortcut == .custom {
            title = customHoldShortcutDefinition?.title ?? "Custom"
        } else {
            title = shortcut.title
        }

        let item = NSMenuItem(
            title: title,
            action: #selector(selectHoldShortcut(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = shortcut.rawValue
        item.state = shortcut == holdShortcut ? .on : .off
        item.isEnabled = !isRecording && !isFinishing
        menu.addItem(item)
    }

    @objc
    private func selectHoldShortcut(_ sender: NSMenuItem) {
        guard !isRecording, !isFinishing,
              let rawValue = sender.representedObject as? String,
              let shortcut = HoldShortcut(rawValue: rawValue),
              shortcut != .custom || customHoldShortcutDefinition != nil else {
            return
        }

        shortcutIsHeld = false
        shortcutOwnsRecording = false
        UserDefaults.standard.set(rawValue, forKey: Self.holdShortcutKey)
    }

    @objc
    private func beginCustomShortcutCapture() {
        guard !isRecording, !isFinishing else {
            return
        }

        shortcutIsHeld = false
        shortcutOwnsRecording = false
        DispatchQueue.main.async { [weak self] in
            self?.showShortcutRecorder()
        }
    }

    private func showShortcutRecorder() {
        let controller = ShortcutRecorderWindowController()
        let recorder = controller.recorder
        if let shortcut = customHoldShortcutDefinition {
            recorder.restore(
                RecordedHoldShortcut(
                    keyCode: shortcut.keyCode,
                    modifiers: shortcut.modifiers,
                    title: shortcut.title
                )
            )
        }

        NSApp.activate(ignoringOtherApps: true)

        isRecordingCustomShortcut = true
        activeShortcutRecorder = recorder
        defer {
            isRecordingCustomShortcut = false
            activeShortcutRecorder = nil
        }
        guard controller.runModal() == .OK,
              let recordedShortcut = recorder.recordedShortcut else {
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(Int(recordedShortcut.keyCode), forKey: Self.customShortcutKeyCodeKey)
        defaults.set(Int(recordedShortcut.modifiers.rawValue), forKey: Self.customShortcutModifiersKey)
        defaults.set(recordedShortcut.title, forKey: Self.customShortcutTitleKey)
        defaults.set(HoldShortcut.custom.rawValue, forKey: Self.holdShortcutKey)
        NSLog("Localix saved custom shortcut %@", recordedShortcut.title)

        if #available(macOS 10.15, *), !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
    }

    private func installHoldShortcutMonitors() {
        let eventMask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) {
            [weak self] event in
            DispatchQueue.main.async {
                self?.handleHoldShortcutEvent(event)
            }
        }
        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) {
            [weak self] event in
            if let self, self.isRecordingCustomShortcut {
                switch event.type {
                case .flagsChanged:
                    self.activeShortcutRecorder?.flagsChanged(with: event)
                case .keyDown:
                    guard let recorder = self.activeShortcutRecorder,
                          recorder.window?.firstResponder === recorder else {
                        return event
                    }
                    recorder.keyDown(with: event)
                default:
                    break
                }
                return nil
            }
            self?.handleHoldShortcutEvent(event)
            return event
        }
    }

    private func removeHoldShortcutMonitors() {
        if let globalShortcutMonitor {
            NSEvent.removeMonitor(globalShortcutMonitor)
            self.globalShortcutMonitor = nil
        }
        if let localShortcutMonitor {
            NSEvent.removeMonitor(localShortcutMonitor)
            self.localShortcutMonitor = nil
        }
    }

    private func handleHoldShortcutEvent(_ event: NSEvent) {
        guard !isRecordingCustomShortcut else {
            return
        }

        guard let shortcut = activeHoldShortcutDefinition,
              event.keyCode == shortcut.keyCode else {
            return
        }

        if shortcut.usesFlagsChanged {
            guard event.type == .flagsChanged else {
                return
            }
            let modifierIsDown = event.modifierFlags.contains(shortcut.modifiers)
            if modifierIsDown, !shortcutIsHeld {
                shortcutIsHeld = true
                activateShortcut()
            } else if !modifierIsDown, shortcutIsHeld {
                shortcutIsHeld = false
                if shortcutBehavior == .hold {
                    releaseHoldShortcut()
                }
            }
            return
        }

        switch event.type {
        case .keyDown:
            let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command, .function])
            guard !event.isARepeat,
                  !shortcutIsHeld,
                  modifiers.contains(shortcut.modifiers) else {
                return
            }
            shortcutIsHeld = true
            activateShortcut()
        case .keyUp:
            guard shortcutIsHeld else {
                return
            }
            shortcutIsHeld = false
            if shortcutBehavior == .hold {
                releaseHoldShortcut()
            }
        default:
            break
        }
    }

    private func activateShortcut() {
        switch shortcutBehavior {
        case .hold:
            guard !isRecording, !isFinishing else {
                shortcutOwnsRecording = false
                return
            }
            shortcutOwnsRecording = true
            beginDictation(requiresShortcutHeld: true)
        case .toggle:
            shortcutOwnsRecording = false
            if isRecording {
                finishRecording(reason: "Shortcut toggled")
            } else if !isFinishing {
                beginDictation()
            }
        }
    }

    private func releaseHoldShortcut() {
        if shortcutOwnsRecording, isRecording {
            finishRecording(reason: "Shortcut released")
        }
        shortcutOwnsRecording = false
    }

    private func addMicrophoneMenu(to menu: NSMenu) {
        let devices = inputDevices()
        let selectedUID = UserDefaults.standard.string(forKey: Self.inputDeviceUIDKey)
        let selectedDevice = selectedUID.flatMap { selectedUID in
            devices.first { audioDeviceUID(for: $0) == selectedUID }
        }
        let defaultDeviceID = defaultInputDeviceID()
        let defaultName = defaultDeviceID.flatMap(audioDeviceName) ?? "Unavailable"
        let microphoneItem = NSMenuItem(
            title: "Microphone: \(preferredInputDeviceName())",
            action: nil,
            keyEquivalent: ""
        )
        let microphoneMenu = NSMenu()

        if selectedUID != nil, selectedDevice == nil {
            let savedName = UserDefaults.standard.string(forKey: Self.inputDeviceNameKey) ?? "Selected microphone"
            let unavailableItem = NSMenuItem(
                title: "\(savedName) is unavailable",
                action: nil,
                keyEquivalent: ""
            )
            unavailableItem.isEnabled = false
            microphoneMenu.addItem(unavailableItem)
            microphoneMenu.addItem(.separator())
        }

        let defaultItem = NSMenuItem(
            title: "System Default (\(defaultName))",
            action: #selector(selectInputDevice(_:)),
            keyEquivalent: ""
        )
        defaultItem.target = self
        defaultItem.representedObject = nil
        defaultItem.state = selectedDevice == nil ? .on : .off
        defaultItem.isEnabled = !isRecording && !isFinishing && defaultDeviceID != nil
        microphoneMenu.addItem(defaultItem)

        if !devices.isEmpty {
            microphoneMenu.addItem(.separator())
        }

        for deviceID in devices {
            guard let name = audioDeviceName(for: deviceID),
                  let uid = audioDeviceUID(for: deviceID) else {
                continue
            }

            let item = NSMenuItem(
                title: name,
                action: #selector(selectInputDevice(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = uid
            item.state = uid == selectedUID ? .on : .off
            item.isEnabled = !isRecording && !isFinishing
            microphoneMenu.addItem(item)
        }

        microphoneItem.submenu = microphoneMenu
        menu.addItem(microphoneItem)
    }

    private func focusedTextTargetDescription() -> String {
        guard let target = focusedTextTarget() else {
            if let applicationName = frontmostExternalApplicationName() {
                return applicationName
            }

            return AXIsProcessTrusted() ? "Not found" : "Accessibility permission required"
        }

        guard let applicationName = target.applicationName else {
            return target.controlName
        }

        return "\(applicationName) · \(target.controlName)"
    }

    private func focusedTextTarget() -> FocusedTextTarget? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }

        let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)
        guard let controlName = focusedTextControlName(for: focusedElement) else {
            return nil
        }

        var processID: pid_t = 0
        var applicationName: String?
        if AXUIElementGetPid(focusedElement, &processID) == .success {
            applicationName = NSRunningApplication(processIdentifier: processID)
                .flatMap(applicationDisplayName)
        }

        return FocusedTextTarget(
            applicationName: applicationName,
            controlName: controlName
        )
    }

    private func focusedTextControlName(for element: AXUIElement) -> String? {
        guard let role = accessibilityStringAttribute(kAXRoleAttribute, from: element) else {
            return nil
        }

        switch role {
        case kAXTextFieldRole:
            if accessibilityStringAttribute(kAXSubroleAttribute, from: element) == kAXSearchFieldSubrole {
                return "Search field"
            }
            return "Text field"
        case kAXTextAreaRole:
            return "Text area"
        case kAXComboBoxRole:
            return "Combo box"
        default:
            return nil
        }
    }

    private func accessibilityStringAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }

        return value as? String
    }

    private func recordFocusedApplicationForSession() {
        let applicationName = focusedTextTarget()?.applicationName
            ?? frontmostExternalApplicationName()
        guard let applicationName,
              !applicationName.isEmpty,
              applicationName != "Localix",
              !sessionApplicationNames.contains(applicationName) else {
            return
        }

        sessionApplicationNames.append(applicationName)
    }

    private func frontmostExternalApplicationName() -> String? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }

        return applicationDisplayName(application)
    }

    private func applicationDisplayName(_ application: NSRunningApplication) -> String? {
        if let bundleURL = application.bundleURL {
            let bundleName = FileManager.default.displayName(atPath: bundleURL.path)
            let name = bundleName.hasSuffix(".app")
                ? String(bundleName.dropLast(4))
                : bundleName
            if !name.isEmpty {
                return name
            }
        }

        return application.localizedName
    }

    @objc
    private func selectInputDevice(_ sender: NSMenuItem) {
        guard !isRecording, !isFinishing else {
            return
        }

        if let uid = sender.representedObject as? String,
           let deviceID = inputDevices().first(where: { audioDeviceUID(for: $0) == uid }) {
            UserDefaults.standard.set(uid, forKey: Self.inputDeviceUIDKey)
            UserDefaults.standard.set(audioDeviceName(for: deviceID), forKey: Self.inputDeviceNameKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.inputDeviceUIDKey)
            UserDefaults.standard.removeObject(forKey: Self.inputDeviceNameKey)
        }
    }

    private func addHistoryMenu(to menu: NSMenu) {
        let historyItem = NSMenuItem(title: "Recent History", action: nil, keyEquivalent: "")
        let historyMenu = NSMenu()
        let entries = loadHistory()

        if entries.isEmpty {
            let emptyItem = NSMenuItem(title: "No sessions yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historyMenu.addItem(emptyItem)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short

            for entry in entries.prefix(10) {
                let wordLabel = entry.wordCount == 1 ? "1 word" : "\(entry.wordCount) words"
                let item = NSMenuItem(
                    title: "\(formatter.string(from: entry.date)) · \(historyApplicationLabel(for: entry)) · \(wordLabel) · \(entry.reason)",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                historyMenu.addItem(item)
            }
        }

        historyItem.submenu = historyMenu
        menu.addItem(historyItem)
    }

    private func historyApplicationLabel(for entry: DictationHistoryEntry) -> String {
        guard let applicationNames = entry.applicationNames, !applicationNames.isEmpty else {
            return "App unknown"
        }

        if applicationNames.count <= 2 {
            return applicationNames.joined(separator: ", ")
        }

        return "\(applicationNames[0]), \(applicationNames[1]) +\(applicationNames.count - 2)"
    }

    private func addTimeoutMenu(
        to menu: NSMenu,
        title: String,
        selectedMinutes: Int,
        action: Selector,
        options: [Int]
    ) {
        let timeoutItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let timeoutMenu = NSMenu()

        for minutes in options {
            let optionTitle = minutes == 0 ? "Off" : minutes == 1 ? "1 minute" : "\(minutes) minutes"
            let option = NSMenuItem(title: optionTitle, action: action, keyEquivalent: "")
            option.target = self
            option.tag = minutes
            option.state = minutes == selectedMinutes ? .on : .off
            timeoutMenu.addItem(option)
        }

        timeoutItem.submenu = timeoutMenu
        menu.addItem(timeoutItem)
    }

    @objc
    private func setAutoStopMinutes(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: Self.autoStopMinutesKey)
        if isRecording {
            scheduleAutoStopTimer()
        }
    }

    @objc
    private func setSilenceTimeoutMinutes(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: Self.silenceTimeoutMinutesKey)
        if isRecording {
            resetSilenceTimer()
        }
    }

    private func beginDictation(requiresShortcutHeld: Bool = false) {
        guard ensureAccessibilityPermission() else {
            showError(
                title: "Accessibility permission required",
                message: "Allow Localix in System Settings > Privacy & Security > Accessibility, then click the microphone again."
            )
            return
        }

        requestSpeechPermission { [weak self] speechAllowed in
            guard let self else {
                return
            }
            guard speechAllowed else {
                self.showError(
                    title: "Speech Recognition permission required",
                    message: "Allow Localix in System Settings > Privacy & Security > Speech Recognition."
                )
                return
            }

            self.requestMicrophonePermission { [weak self] microphoneAllowed in
                guard let self else {
                    return
                }
                guard microphoneAllowed else {
                    self.showError(
                        title: "Microphone permission required",
                        message: "Allow Localix in System Settings > Privacy & Security > Microphone."
                    )
                    return
                }

                guard !requiresShortcutHeld || self.shortcutIsHeld else {
                    self.shortcutOwnsRecording = false
                    return
                }

                self.sessionText = ""
                self.sessionApplicationNames = []
                self.recordFocusedApplicationForSession()
                self.sessionStartedAt = Date()
                self.pendingStopReason = "Stopped manually"
                self.hasStartedSessionTimers = false
                self.startRecording()
            }
        }
    }

    private func ensureAccessibilityPermission() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func requestSpeechPermission(completion: @escaping (Bool) -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            completion(true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    completion(status == .authorized)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                DispatchQueue.main.async {
                    completion(allowed)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    private func startRecording() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) else {
            showError(
                title: "Language unavailable",
                message: "Speech Recognition does not support the current macOS language."
            )
            return
        }

        guard recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            showError(
                title: "Local recognition unavailable",
                message: "On-device Speech Recognition is unavailable for the current language. No audio was sent anywhere."
            )
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request
        transcript = ""
        deliveredTranscript = ""

        let inputNode = audioEngine.inputNode
        guard let inputDeviceID = preferredInputDeviceID(),
              applyInputDevice(inputDeviceID, to: inputNode),
              let format = audioDeviceInputFormat(for: inputDeviceID) else {
            recognitionRequest = nil
            showError(
                title: "Microphone unavailable",
                message: "Localix could not connect to the selected microphone. Choose another microphone from the right-click menu."
            )
            return
        }
        guard format.channelCount > 0 else {
            recognitionRequest = nil
            showError(title: "Microphone unavailable", message: "macOS did not provide a microphone input.")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        recognitionGeneration += 1
        let generation = recognitionGeneration
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, generation == self.recognitionGeneration else {
                    return
                }

                if let result {
                    let updatedTranscript = result.bestTranscription.formattedString
                    if !updatedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.transcript = updatedTranscript
                        self.deliverTranscriptUpdate(updatedTranscript)
                        self.resetSilenceTimer()
                    }
                    if result.isFinal {
                        if self.isRecording {
                            self.restartRecognitionAfterSilence()
                        } else {
                            self.completeRecognition()
                        }
                    }
                }

                if let error, self.isRecording || self.isFinishing {
                    NSLog("Localix recognition error: %@", error.localizedDescription)
                    if self.isRecording {
                        self.finishRecording(reason: "Recognition error")
                        self.completeRecognition()
                        self.showError(
                            title: "Speech Recognition stopped",
                            message: "macOS stopped the local recognition session. Try starting dictation again."
                        )
                    } else {
                        self.completeRecognition()
                    }
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            if !hasStartedSessionTimers {
                hasStartedSessionTimers = true
                scheduleAutoStopTimer()
                resetSilenceTimer()
            }
            updateStatusIcon()
        } catch {
            inputNode.removeTap(onBus: 0)
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            sessionStartedAt = nil
            hasStartedSessionTimers = false
            invalidateSessionTimers()
            showError(title: "Could not start dictation", message: error.localizedDescription)
        }
    }

    private func restartRecognitionAfterSilence() {
        guard isRecording else {
            return
        }

        isRecording = false
        recognitionGeneration += 1
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        DispatchQueue.main.async { [weak self] in
            self?.startRecording()
        }
    }

    private func deliverTranscriptUpdate(_ updatedTranscript: String) {
        guard updatedTranscript != deliveredTranscript else {
            return
        }

        if deliveredTranscript.isEmpty {
            let needsSeparator = sessionText.last.map { !$0.isWhitespace } == true
                && updatedTranscript.first.map { !$0.isWhitespace } == true
            postUnicodeText((needsSeparator ? " " : "") + updatedTranscript)
            deliveredTranscript = updatedTranscript
            return
        }

        let deliveredCharacters = Array(deliveredTranscript)
        let updatedCharacters = Array(updatedTranscript)

        if deliveredCharacters.count >= 20 && updatedCharacters.count * 2 < deliveredCharacters.count {
            postUnicodeText(" " + updatedTranscript)
            deliveredTranscript = updatedTranscript
            return
        }

        if updatedTranscript.hasPrefix(deliveredTranscript) {
            postUnicodeText(String(updatedTranscript.dropFirst(deliveredTranscript.count)))
            deliveredTranscript = updatedTranscript
            return
        }

        let deliveredWords = deliveredTranscript.split(whereSeparator: \.isWhitespace)
        let updatedWords = updatedTranscript.split(whereSeparator: \.isWhitespace)
        if updatedWords.count > deliveredWords.count {
            let newWords = updatedWords.dropFirst(deliveredWords.count).joined(separator: " ")
            postUnicodeText(" " + newWords)
        }

        deliveredTranscript = updatedTranscript
    }

    private func postUnicodeText(_ text: String) {
        guard let source = CGEventSource(stateID: .privateState) else {
            return
        }

        recordFocusedApplicationForSession()
        sessionText += text
        let characters = Array(text.utf16)
        let chunkSize = 20
        for startIndex in stride(from: 0, to: characters.count, by: chunkSize) {
            let endIndex = min(startIndex + chunkSize, characters.count)
            var chunk = Array(characters[startIndex..<endIndex])
            guard let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: true
            ), let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: false
            ) else {
                return
            }

            keyDown.keyboardSetUnicodeString(
                stringLength: chunk.count,
                unicodeString: &chunk
            )
            keyDown.flags = []
            keyUp.flags = []
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func preferredInputDeviceID() -> AudioDeviceID? {
        if let selectedUID = UserDefaults.standard.string(forKey: Self.inputDeviceUIDKey),
           let selectedDevice = inputDevices().first(where: { audioDeviceUID(for: $0) == selectedUID }) {
            return selectedDevice
        }

        return defaultInputDeviceID()
    }

    private func preferredInputDeviceName() -> String {
        guard let deviceID = preferredInputDeviceID() else {
            return "Unavailable"
        }

        let name = audioDeviceName(for: deviceID) ?? "Unknown"
        if UserDefaults.standard.string(forKey: Self.inputDeviceUIDKey) != nil,
           audioDeviceUID(for: deviceID) != UserDefaults.standard.string(forKey: Self.inputDeviceUIDKey) {
            return "\(name) (selected microphone unavailable)"
        }

        return name
    }

    private func defaultInputDeviceID() -> AudioDeviceID? {
        audioDeviceID(
            for: kAudioHardwarePropertyDefaultInputDevice,
            objectID: AudioObjectID(kAudioObjectSystemObject)
        )
    }

    private func inputDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else {
            return []
        }

        var deviceIDs = [AudioDeviceID](repeating: kAudioObjectUnknown, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs
            .filter(audioDeviceHasInput)
            .sorted {
                (audioDeviceName(for: $0) ?? "").localizedCaseInsensitiveCompare(
                    audioDeviceName(for: $1) ?? ""
                ) == .orderedAscending
            }
    }

    private func audioDeviceHasInput(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
    }

    private func audioDeviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedUID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanagedUID)
        guard status == noErr, let unmanagedUID else {
            return nil
        }

        return unmanagedUID.takeUnretainedValue() as String
    }

    private func applyInputDevice(
        _ deviceID: AudioDeviceID,
        to inputNode: AVAudioInputNode
    ) -> Bool {
        guard let audioUnit = inputNode.audioUnit else {
            return false
        }

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        return status == noErr
    }

    private func audioDeviceInputFormat(for deviceID: AudioDeviceID) -> AVAudioFormat? {
        var sampleRateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate = Float64.zero
        var sampleRateSize = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(
            deviceID,
            &sampleRateAddress,
            0,
            nil,
            &sampleRateSize,
            &sampleRate
        ) == noErr,
        sampleRate > 0 else {
            return nil
        }

        var streamAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var bufferListSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceID,
            &streamAddress,
            0,
            nil,
            &bufferListSize
        ) == noErr,
        bufferListSize >= MemoryLayout<AudioBufferList>.size else {
            return nil
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(bufferListSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            bufferListPointer.deallocate()
        }

        let audioBufferList = bufferListPointer.bindMemory(
            to: AudioBufferList.self,
            capacity: 1
        )
        guard AudioObjectGetPropertyData(
            deviceID,
            &streamAddress,
            0,
            nil,
            &bufferListSize,
            audioBufferList
        ) == noErr else {
            return nil
        }

        let channelCount = UnsafeMutableAudioBufferListPointer(audioBufferList)
            .reduce(0) { $0 + Int($1.mNumberChannels) }
        guard channelCount > 0,
              channelCount <= Int(UInt32.max),
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channelCount),
                interleaved: false
              ) else {
            return nil
        }

        return format
    }

    private func audioDeviceID(
        for selector: AudioObjectPropertySelector,
        objectID: AudioObjectID
    ) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    private func audioDeviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanagedName)
        guard status == noErr, let unmanagedName else {
            return nil
        }

        return unmanagedName.takeUnretainedValue() as String
    }

    private func scheduleAutoStopTimer() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil

        guard autoStopMinutes > 0, let sessionStartedAt else {
            return
        }

        let deadline = sessionStartedAt.addingTimeInterval(TimeInterval(autoStopMinutes * 60))
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            finishRecording(reason: "Auto stop")
            return
        }

        let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            self?.finishRecording(reason: "Auto stop")
        }
        autoStopTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        guard silenceTimeoutMinutes > 0, isRecording else {
            return
        }

        let timer = Timer(
            timeInterval: TimeInterval(silenceTimeoutMinutes * 60),
            repeats: false
        ) { [weak self] _ in
            self?.finishRecording(reason: "Silence timeout")
        }
        silenceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func invalidateSessionTimers() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    private func finishRecording(reason: String = "Stopped manually") {
        guard isRecording else {
            return
        }

        pendingStopReason = reason
        invalidateSessionTimers()
        isRecording = false
        isFinishing = true
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        updateStatusIcon()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.isFinishing else {
                return
            }

            self.completeRecognition()
        }
    }

    private func completeRecognition() {
        if isRecording {
            isRecording = false
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
        }

        isFinishing = false
        recognitionGeneration += 1
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        updateStatusIcon()

        let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = ""
        deliveredTranscript = ""
        recordHistoryIfNeeded()
        NSLog("Localix completed session with %d characters", finalTranscript.count)
    }

    private func recordHistoryIfNeeded() {
        guard let sessionStartedAt else {
            return
        }

        let wordCount = sessionText.split(whereSeparator: \.isWhitespace).count
        let entry = DictationHistoryEntry(
            date: sessionStartedAt,
            wordCount: wordCount,
            reason: pendingStopReason,
            applicationNames: sessionApplicationNames.isEmpty ? nil : sessionApplicationNames
        )
        var entries = loadHistory()
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(25))

        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }

        self.sessionStartedAt = nil
        sessionText = ""
        sessionApplicationNames = []
        pendingStopReason = "Stopped manually"
        hasStartedSessionTimers = false
    }

    private func loadHistory() -> [DictationHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let entries = try? JSONDecoder().decode([DictationHistoryEntry].self, from: data) else {
            return []
        }

        return entries
    }

    private func updateStatusIcon() {
        let symbolName = isFinishing ? "ellipsis.circle" : "text.bubble"
        let description = isRecording ? "Stop Localix" : isFinishing ? "Finishing local transcription" : "Start Localix"
        statusItem.length = isRecording ? 34 : NSStatusItem.squareLength
        statusItem.button?.image = statusImage(
            symbolName: symbolName,
            accessibilityDescription: description,
            hasRedBackground: isRecording
        )
        statusItem.button?.title = ""
        statusItem.button?.contentTintColor = nil
        statusItem.button?.toolTip = isRecording ? "Recording locally. Click to stop." : isFinishing ? "Finishing on-device transcription." : "Localix"
    }

    private func statusImage(
        symbolName: String,
        accessibilityDescription: String,
        hasRedBackground: Bool
    ) -> NSImage? {
        guard let symbol = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        ) else {
            return nil
        }

        guard hasRedBackground else {
            symbol.isTemplate = true
            return symbol
        }

        let whiteSymbol = symbol.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [.white])
        ) ?? symbol
        let image = NSImage(size: NSSize(width: 30, height: 24), flipped: false) { rect in
            NSColor.systemRed.setFill()
            NSBezierPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                xRadius: 5,
                yRadius: 5
            ).fill()
            whiteSymbol.draw(
                in: NSRect(
                    x: rect.midX - 6,
                    y: rect.midY - 6,
                    width: 12,
                    height: 12
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    private func showError(title: String, message: String) {
        NSLog("Localix error: %@: %@", title, message)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@main
enum LocalixApp {
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.run()
    }
}
