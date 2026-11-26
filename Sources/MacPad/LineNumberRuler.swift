import AppKit

/// Line-number gutter. Click a number to select that line.
final class LineNumberRuler: NSRulerView {
    private weak var textView: EditorTextView?
    private let lineIndex: LineIndex
    private var numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    init(textView: EditorTextView, scrollView: NSScrollView, lineIndex: LineIndex) {
        self.textView = textView
        self.lineIndex = lineIndex
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    func setEditorFontSize(_ size: CGFloat) {
        numberFont = NSFont.monospacedDigitSystemFont(ofSize: max(9, size - 2), weight: .regular)
        updateThickness()
        needsDisplay = true
    }

    func updateThickness() {
        let digits = max(3, String(lineIndex.count).count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: numberFont]).width
        let width = ceil(CGFloat(digits) * digitWidth + 18)
        if abs(ruleThickness - width) > 0.5 { ruleThickness = width }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        Theme.gutterBackground.setFill()
        bounds.intersection(rect).fill()
        Theme.separator.setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let text = tv.string as NSString
        let length = text.length
        let visible = tv.visibleRect
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let starts = lineIndex.starts
        let currentLine = lineIndex.line(containing: tv.selectedRange().location)
        let yOffset = convert(NSPoint.zero, from: tv).y + tv.textContainerOrigin.y

        let normal: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: Theme.gutterText]
        let current: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: Theme.gutterCurrent]

        var line = lineIndex.line(containing: charRange.location)
        while line < starts.count {
            let start = starts[line]
            if start > length || start > NSMaxRange(charRange) { break }
            let fragment: NSRect
            if start == length {
                fragment = lm.extraLineFragmentRect
            } else {
                let glyph = lm.glyphIndexForCharacter(at: start)
                fragment = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            if fragment.height > 0 {
                let label = "\(line + 1)" as NSString
                let attrs = line == currentLine ? current : normal
                let size = label.size(withAttributes: attrs)
                let y = yOffset + fragment.minY + (fragment.height - size.height) / 2
                label.draw(at: NSPoint(x: ruleThickness - size.width - 9, y: y), withAttributes: attrs)
            }
            line += 1
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let point = tv.convert(event.locationInWindow, from: nil)
        let glyph = lm.glyphIndex(for: NSPoint(x: 0, y: point.y - tv.textContainerOrigin.y), in: tc)
        let charIndex = lm.characterIndexForGlyph(at: glyph)
        let text = tv.string as NSString
        let range = text.lineRange(for: NSRange(location: min(charIndex, text.length), length: 0))
        tv.setSelectedRange(range)
        tv.window?.makeFirstResponder(tv)
    }
}
