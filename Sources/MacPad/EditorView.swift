import AppKit

/// Scroll view + text view + line-number gutter for one document.
final class EditorView: NSView, NSTextViewDelegate {
    let scrollView: NSScrollView
    let textView: EditorTextView
    let lineIndex: LineIndex
    private var wraps = false
    private let ruler: LineNumberRuler
    private let undo = UndoManager()
    private var highlightWork: DispatchWorkItem?
    private var previewWork: DispatchWorkItem?
    private var splitView: NSSplitView?
    private var preview: MarkdownPreviewView?

    private var isApplyingRenderedEdit = false
    /// YAML front matter is kept out of the rendered view and re-attached on edits.
    private var frontMatter = ""

    enum ViewMode: String {
        case source, split, rendered
    }
    private(set) var viewMode: ViewMode = .source

    var isPreviewVisible: Bool { viewMode == .split }
    var isRendered: Bool { viewMode == .rendered }

    /// Folder used to resolve relative image paths in the Markdown preview.
    var previewBaseURL: URL? {
        didSet {
            guard oldValue != previewBaseURL, let preview else { return }
            preview.baseURL = previewBaseURL
            preview.update(markdown: renderSource(), reload: true)
        }
    }
    private static let fullHighlightLimit = 1_500_000

    var onTextChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?
    var onViewModeChange: (() -> Void)?

    var language: Language {
        didSet { applyLanguage() }
    }

    init(text: String, language: Language) {
        self.language = language
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                              height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        let sv = NSScrollView()
        let index = LineIndex()
        let tv0 = EditorTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        scrollView = sv
        lineIndex = index
        textView = tv0
        ruler = LineNumberRuler(textView: tv0, scrollView: sv, lineIndex: index)
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 400))

        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        addSubview(scrollView)

        let tv = textView
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = false
        tv.isIncrementalSearchingEnabled = false
        tv.usesFontPanel = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.backgroundColor = .textBackgroundColor
        tv.drawsBackground = true
        tv.insertionPointColor = .textColor
        tv.textContainerInset = NSSize(width: 2, height: 4)
        tv.isVerticallyResizable = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask = [.width]
        tv.delegate = self
        tv.registerForDraggedTypes(tv.registeredDraggedTypes + [.fileURL])
        scrollView.documentView = tv

        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true

        let ns = text as NSString
        layoutManager.allowsNonContiguousLayout = ns.length > 300_000
        applyPreferences()
        storage.setAttributedString(NSAttributedString(string: text, attributes: tv.baseAttributes))
        lineIndex.rebuild(ns)
        ruler.updateThickness()
        applyLanguage()
        tv.setSelectedRange(NSRange(location: 0, length: 0))

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(didScroll(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        scrollView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewResized(_:)),
                                               name: NSView.frameDidChangeNotification, object: scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Configuration

    func applyPreferences() {
        let tv = textView
        let font = Prefs.editorFont
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = []
        paragraph.defaultTabInterval = spaceWidth * CGFloat(Prefs.tabWidth)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraph,
        ]
        tv.baseAttributes = attrs
        tv.typingAttributes = attrs
        tv.font = font
        if let storage = tv.textStorage, storage.length > 0 {
            storage.beginEditing()
            storage.setAttributes(attrs, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }
        tv.tabWidth = Prefs.tabWidth
        tv.useSpaces = Prefs.useSpaces
        tv.autoIndent = Prefs.autoIndent
        tv.highlightCurrentLine = Prefs.highlightCurrentLine
        tv.layoutManager?.showsInvisibleCharacters = Prefs.showInvisibles
        scrollView.rulersVisible = Prefs.showLineNumbers
        ruler.setEditorFontSize(font.pointSize)
        setWordWrap(Prefs.wordWrap)
        tv.needsDisplay = true
        scheduleHighlight(delay: 0)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        updateMinSize()
    }

    private func updateMinSize() {
        let size = scrollView.contentSize
        textView.minSize = NSSize(width: wraps ? 0 : size.width, height: size.height)
        if !wraps && textView.frame.width < size.width {
            textView.setFrameSize(NSSize(width: size.width, height: textView.frame.height))
        }
    }

    func setWordWrap(_ wrap: Bool) {
        guard let container = textView.textContainer else { return }
        wraps = wrap
        defer { updateMinSize() }
        scrollView.hasHorizontalScroller = !wrap
        textView.isHorizontallyResizable = !wrap
        container.widthTracksTextView = wrap
        if wrap {
            let width = scrollView.contentSize.width
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        } else {
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.sizeToFit()
        }
    }

    @objc private func scrollViewResized(_ note: Notification) {
        updateMinSize()
    }

    // MARK: - Markdown views (source / split / rendered)

    /// Kept for the "Show Preview" toggle.
    func setPreviewVisible(_ show: Bool) {
        setViewMode(show ? .split : .source)
    }

    func setViewMode(_ mode: ViewMode) {
        guard mode != viewMode else { return }
        if viewMode == .rendered, let preview {
            // Pull in the last edits before leaving the rendered editor.
            preview.flushEdits { [weak self] in self?.applyViewMode(mode) }
        } else {
            applyViewMode(mode)
        }
    }

    private func applyViewMode(_ mode: ViewMode) {
        guard mode != viewMode else { return }
        let hadFocus = window?.firstResponder === textView || (preview?.containsFirstResponder ?? false)
        preview?.removeFromSuperview()
        preview = nil
        splitView?.removeFromSuperview()
        splitView = nil
        scrollView.removeFromSuperview()
        viewMode = mode

        switch mode {
        case .source:
            scrollView.frame = bounds
            scrollView.autoresizingMask = [.width, .height]
            addSubview(scrollView)
        case .split:
            let half = floor(bounds.width / 2)
            let split = NSSplitView(frame: bounds)
            split.isVertical = true
            split.dividerStyle = .thin
            split.autoresizingMask = [.width, .height]
            let p = MarkdownPreviewView(frame: NSRect(x: half + 1, y: 0, width: bounds.width - half - 1, height: bounds.height),
                                        editable: false)
            p.baseURL = previewBaseURL
            scrollView.frame = NSRect(x: 0, y: 0, width: half, height: bounds.height)
            split.addSubview(scrollView)
            split.addSubview(p)
            addSubview(split)
            split.adjustSubviews()
            split.setPosition(half, ofDividerAt: 0)
            splitView = split
            preview = p
            p.update(markdown: renderSource(), reload: true)
            p.scroll(toFraction: editorScrollFraction())
        case .rendered:
            let p = MarkdownPreviewView(frame: bounds, editable: true)
            p.autoresizingMask = [.width, .height]
            p.baseURL = previewBaseURL
            p.onMarkdownEdited = { [weak self] markdown in self?.applyRenderedEdit(markdown) }
            addSubview(p)
            preview = p
            p.update(markdown: renderSource(), reload: true)
        }
        updateMinSize()
        if hadFocus { focus() }
        onViewModeChange?()
    }

    /// Gives keyboard focus to whichever view is editing this document.
    func focus() {
        if viewMode == .rendered, let preview {
            preview.focusEditor()
        } else {
            window?.makeFirstResponder(textView)
        }
    }

    /// Delivers pending edits from the rendered editor (call before saving).
    func flushRenderedEdits(_ completion: @escaping () -> Void) {
        if viewMode == .rendered, let preview {
            preview.flushEdits(completion)
        } else {
            completion()
        }
    }

    func runRenderedCommand(_ name: String) {
        preview?.runCommand(name)
    }

    var renderedHasFocus: Bool {
        viewMode == .rendered && (preview?.containsFirstResponder ?? false)
    }

    func findInRendered(_ text: String, backwards: Bool, caseSensitive: Bool, wraps: Bool, completion: @escaping (Bool) -> Void) {
        guard let preview else { completion(false); return }
        preview.find(text, backwards: backwards, caseSensitive: caseSensitive, wraps: wraps, completion: completion)
    }

    /// Markdown to render, without YAML front matter (remembered so it can be re-attached).
    private func renderSource() -> String {
        let text = textView.string
        frontMatter = ""
        guard text.hasPrefix("---\n") else { return text }
        let ns = text as NSString
        let close = ns.range(of: "\n---\n", options: [], range: NSRange(location: 3, length: ns.length - 3))
        guard close.location != NSNotFound else { return text }
        let end = NSMaxRange(close)
        frontMatter = ns.substring(to: end)
        return ns.substring(from: end)
    }

    private func applyRenderedEdit(_ markdown: String) {
        let full = frontMatter + markdown
        guard full != textView.string else { return }
        isApplyingRenderedEdit = true
        replaceAllText(with: full)
        isApplyingRenderedEdit = false
    }

    private func schedulePreview() {
        guard preview != nil, !isApplyingRenderedEdit else { return }
        previewWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let preview = self.preview else { return }
            preview.update(markdown: self.renderSource())
        }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func editorScrollFraction() -> CGFloat {
        let clip = scrollView.contentView
        let docHeight = textView.frame.height
        let range = docHeight - clip.bounds.height
        return range > 0 ? clip.bounds.minY / range : 0
    }

    private func applyLanguage() {
        textView.markdownMode = language.id == "markdown"
        textView.lineComment = language.lineComment
        textView.blockComment = language.blockComment
        textView.indentAfterColon = language.indentAfterColon
        scheduleHighlight(delay: 0)
    }

    // MARK: - Text

    /// Replaces the whole text (undoable).
    func replaceAllText(with text: String) {
        let sel = textView.selectedRange()
        let length = (textView.string as NSString).length
        textView.replace(NSRange(location: 0, length: length), with: text)
        let newLength = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(sel.location, newLength), length: 0))
    }

    func goTo(line: Int, column: Int = 0, length: Int = 0) {
        let idx = max(0, min(line - 1, lineIndex.count - 1))
        let textLength = (textView.string as NSString).length
        let location = min(lineIndex.starts[idx] + max(0, column), textLength)
        let range = NSRange(location: location, length: max(0, min(length, textLength - location)))
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        if range.length > 0 { textView.showFindIndicator(for: range) }
        focus()
    }

    /// 1-based line and column of the caret.
    func caretPosition() -> (line: Int, column: Int) {
        let location = textView.selectedRange().location
        let line = lineIndex.line(containing: location)
        return (line + 1, location - lineIndex.starts[line] + 1)
    }

    // MARK: - Marks (Find > Mark All)

    func mark(_ ranges: [NSRange]) {
        guard let lm = textView.layoutManager else { return }
        clearMarks()
        for r in ranges {
            lm.addTemporaryAttribute(.backgroundColor, value: Theme.markBackground, forCharacterRange: r)
        }
    }

    func clearMarks() {
        let length = (textView.string as NSString).length
        textView.layoutManager?.removeTemporaryAttribute(.backgroundColor,
                                                        forCharacterRange: NSRange(location: 0, length: length))
    }

    // MARK: - Highlighting

    func scheduleHighlight(delay: TimeInterval = 0.12) {
        highlightWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.highlightNow() }
        highlightWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func highlightNow() {
        guard let lm = textView.layoutManager else { return }
        let text = textView.string
        let length = (text as NSString).length
        var range = NSRange(location: 0, length: length)
        if length > EditorView.fullHighlightLimit, let tc = textView.textContainer {
            let glyphs = lm.glyphRange(forBoundingRect: textView.visibleRect, in: tc)
            let visible = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let start = max(0, visible.location - 20_000)
            let end = min(length, NSMaxRange(visible) + 20_000)
            range = (text as NSString).lineRange(for: NSRange(location: start, length: end - start))
        }
        Highlighter.highlight(lm, text: text, range: range, language: language)
    }

    @objc private func didScroll(_ note: Notification) {
        ruler.needsDisplay = true
        if viewMode == .split { preview?.scroll(toFraction: editorScrollFraction()) }
        if (textView.string as NSString).length > EditorView.fullHighlightLimit {
            scheduleHighlight(delay: 0.08)
        }
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        lineIndex.rebuild(textView.string as NSString)
        ruler.updateThickness()
        ruler.needsDisplay = true
        scheduleHighlight()
        schedulePreview()
        onTextChange?()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        ruler.needsDisplay = true
        onSelectionChange?()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        undo
    }
}
