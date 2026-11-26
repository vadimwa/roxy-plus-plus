import AppKit

/// Inline Find / Replace bar shown above the editor.
final class FindBarView: NSView, NSTextFieldDelegate {
    enum Action: Int {
        case next = 1, previous, count, markAll, replace, replaceAll, findInFiles, close
    }

    let findField = NSTextField()
    let replaceField = NSTextField()
    let caseBox = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
    let wordBox = NSButton(checkboxWithTitle: "Whole word", target: nil, action: nil)
    let regexBox = NSButton(checkboxWithTitle: "Regular expression", target: nil, action: nil)
    let wrapBox = NSButton(checkboxWithTitle: "Wrap around", target: nil, action: nil)
    let statusLabel = NSTextField(labelWithString: "")
    private var replaceRow: NSStackView!

    var onAction: ((Action) -> Void)?

    var showsReplace = false {
        didSet { replaceRow.isHidden = !showsReplace }
    }

    var options: SearchOptions {
        SearchOptions(query: findField.stringValue,
                      caseSensitive: caseBox.state == .on,
                      wholeWord: wordBox.state == .on,
                      regex: regexBox.state == .on,
                      wrap: wrapBox.state == .on)
    }

    var replacement: String { replaceField.stringValue }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wrapBox.state = .on
        regexBox.toolTip = "ICU regular expressions. In the replacement use $1, $2… for groups and \\n, \\t for newline / tab."

        for (field, placeholder) in [(findField, "Find"), (replaceField, "Replace with")] {
            field.placeholderString = placeholder
            field.delegate = self
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.usesSingleLineMode = true
            field.cell?.isScrollable = true
            field.cell?.wraps = false
            field.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        }
        for box in [caseBox, wordBox, regexBox, wrapBox] {
            box.controlSize = .small
            box.font = .systemFont(ofSize: 11)
        }
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!,
                                   target: self, action: #selector(buttonPressed(_:)))
        closeButton.isBordered = false
        closeButton.tag = Action.close.rawValue
        closeButton.toolTip = "Close (Esc)"

        let row1 = row([label("Find:"), findField,
                        button("◀ Previous", .previous), button("Next ▶", .next),
                        button("Count", .count), button("Mark All", .markAll), closeButton])
        replaceRow = row([label("Replace:"), replaceField,
                          button("Replace", .replace), button("Replace All", .replaceAll),
                          button("Find in Files…", .findInFiles)])
        let row3 = row([label(""), caseBox, wordBox, regexBox, wrapBox, statusLabel])

        let column = NSStackView(views: [row1, replaceRow, row3])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        for r in [row1, replaceRow!, row3] {
            r.trailingAnchor.constraint(equalTo: column.trailingAnchor).isActive = true
        }
        replaceRow.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let r = NSStackView(views: views)
        r.orientation = .horizontal
        r.alignment = .centerY
        r.distribution = .fill
        r.spacing = 6
        return r
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        l.font = .systemFont(ofSize: 12)
        l.widthAnchor.constraint(equalToConstant: 60).isActive = true
        return l
    }

    private func button(_ title: String, _ action: Action) -> NSButton {
        let b = NSButton(title: title, target: self, action: #selector(buttonPressed(_:)))
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.font = .systemFont(ofSize: 11)
        b.tag = action.rawValue
        b.setContentHuggingPriority(.required, for: .horizontal)
        return b
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        if let action = Action(rawValue: sender.tag) { onAction?(action) }
    }

    func setStatus(_ text: String, isError: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.barBackground.setFill()
        bounds.fill()
        Theme.separator.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    // Enter = next (Shift+Enter = previous, Enter in Replace = replace), Esc = close
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if control === replaceField {
                onAction?(.replace)
            } else {
                let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                onAction?(shift ? .previous : .next)
            }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onAction?(.close)
            return true
        }
        return false
    }
}
