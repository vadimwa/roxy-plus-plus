import AppKit

/// Bottom bar: caret position, document stats, and pickers for language, line ending and encoding.
final class StatusBarView: NSView {
    let positionLabel = NSTextField(labelWithString: "")
    let infoLabel = NSTextField(labelWithString: "")
    let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let lineEndingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let encodingPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    let modeControl = NSSegmentedControl(labels: ["Formatted", "Split", "Source"], trackingMode: .selectOne,
                                         target: nil, action: nil)

    /// 3 = formatted (rendered), 2 = split, 1 = source — same tags as the Markdown menu.
    var onMarkdownMode: ((Int) -> Void)?
    var onLanguage: ((String) -> Void)?
    var onLineEnding: ((LineEnding) -> Void)?
    var onEncoding: ((FileEncoding) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)

        for label in [positionLabel, infoLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
        }
        infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        languagePopup.addItems(withTitles: Language.all.map { $0.name })
        lineEndingPopup.addItems(withTitles: LineEnding.allCases.map { $0.label })
        encodingPopup.addItems(withTitles: FileEncoding.allCases.map { $0.label })
        languagePopup.action = #selector(languageChanged(_:))
        lineEndingPopup.action = #selector(lineEndingChanged(_:))
        encodingPopup.action = #selector(encodingChanged(_:))
        languagePopup.toolTip = "Language (syntax highlighting)"
        lineEndingPopup.toolTip = "Line endings used when saving"
        encodingPopup.toolTip = "Encoding used when saving"
        for popup in [languagePopup, lineEndingPopup, encodingPopup] {
            popup.target = self
            popup.controlSize = .small
            popup.font = .systemFont(ofSize: 11)
            popup.isBordered = false
            popup.setContentHuggingPriority(.required, for: .horizontal)
        }

        modeControl.controlSize = .small
        modeControl.font = .systemFont(ofSize: 11)
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        modeControl.toolTip = "How to show this Markdown file"
        modeControl.isHidden = true
        modeControl.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let stack = NSStackView(views: [positionLabel, infoLabel, spacer, modeControl, languagePopup, lineEndingPopup, encodingPopup])
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.alignment = .centerY
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.barBackground.setFill()
        bounds.fill()
        Theme.separator.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    func update(position: String, info: String, languageID: String, lineEnding: LineEnding, encoding: FileEncoding) {
        positionLabel.stringValue = position
        infoLabel.stringValue = info
        if let i = Language.all.firstIndex(where: { $0.id == languageID }) { languagePopup.selectItem(at: i) }
        if let i = LineEnding.allCases.firstIndex(of: lineEnding) { lineEndingPopup.selectItem(at: i) }
        if let i = FileEncoding.allCases.firstIndex(of: encoding) { encodingPopup.selectItem(at: i) }
    }

    /// Terminal tabs hide the language / line ending / encoding controls.
    func setTerminalMode(_ on: Bool) {
        for view in [languagePopup, lineEndingPopup, encodingPopup] as [NSView] { view.isHidden = on }
        if on { modeControl.isHidden = true }
    }

    /// `mode`: 3 formatted, 2 split, 1 source; nil hides the control (non-Markdown files).
    func setMarkdownMode(_ mode: Int?) {
        guard let mode else { modeControl.isHidden = true; return }
        modeControl.isHidden = false
        modeControl.selectedSegment = [3: 0, 2: 1, 1: 2][mode] ?? 2
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        let tags = [3, 2, 1]
        guard tags.indices.contains(sender.selectedSegment) else { return }
        onMarkdownMode?(tags[sender.selectedSegment])
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem
        guard Language.all.indices.contains(i) else { return }
        onLanguage?(Language.all[i].id)
    }

    @objc private func lineEndingChanged(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem
        guard LineEnding.allCases.indices.contains(i) else { return }
        onLineEnding?(LineEnding.allCases[i])
    }

    @objc private func encodingChanged(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem
        guard FileEncoding.allCases.indices.contains(i) else { return }
        onEncoding?(FileEncoding.allCases[i])
    }
}
