import AppKit

/// NSTextView with code-editor behaviour: auto-indent, tab/shift-tab block indent, current-line highlight,
/// line operations, and multi-cursor / multi-selection editing.
final class EditorTextView: NSTextView {
    var baseAttributes: [NSAttributedString.Key: Any] = [:]
    var highlightCurrentLine = true
    var tabWidth = 4
    var useSpaces = true
    var autoIndent = true
    var indentAfterColon = false
    var markdownMode = false
    var lineComment: String?
    var blockComment: (String, String)?
    var onOpenFiles: (([URL]) -> Void)?

    /// Extra insertion points (UTF-16 offsets). Active when it holds more than one caret.
    private(set) var multiCarets: [Int] = []
    private var settingCarets = false

    var ns: NSString { string as NSString }
    var indentUnit: String { useSpaces ? String(repeating: " ", count: tabWidth) : "\t" }

    // MARK: - Editing primitives

    /// Replaces a range as one undoable step.
    func replace(_ range: NSRange, with text: String, select newSelection: [NSRange]? = nil) {
        breakUndoCoalescing()
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: baseAttributes))
        didChangeText()
        if let newSelection, !newSelection.isEmpty {
            selectedRanges = newSelection.map { NSValue(range: $0) }
        }
    }

    /// Applies several non-overlapping edits as a single undoable change.
    /// Returns the ranges of the inserted texts in the new document, sorted by location.
    @discardableResult
    func applyEdits(_ edits: [(NSRange, String)]) -> [NSRange] {
        guard !edits.isEmpty else { return [] }
        let sorted = edits.sorted { $0.0.location < $1.0.location }
        let text = ns
        let start = sorted[0].0.location
        let end = sorted.map { NSMaxRange($0.0) }.max() ?? start
        let out = NSMutableString()
        var cursor = start
        var delta = 0
        var inserted: [NSRange] = []
        for (range, replacement) in sorted {
            guard range.location >= cursor else { continue } // skip overlaps
            if range.location > cursor {
                out.append(text.substring(with: NSRange(location: cursor, length: range.location - cursor)))
            }
            let len = (replacement as NSString).length
            inserted.append(NSRange(location: range.location + delta, length: len))
            out.append(replacement)
            delta += len - range.length
            cursor = NSMaxRange(range)
        }
        replace(NSRange(location: start, length: end - start), with: out as String)
        return inserted
    }

    // MARK: - Multi-cursor

    func setMultiCarets(_ positions: [Int]) {
        let unique = Array(Set(positions)).sorted()
        settingCarets = true
        setSelectedRange(NSRange(location: unique.last ?? 0, length: 0))
        settingCarets = false
        multiCarets = unique.count > 1 ? unique : []
        needsDisplay = true
    }

    func clearMultiCarets() {
        guard !multiCarets.isEmpty else { return }
        multiCarets = []
        needsDisplay = true
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !settingCarets && !multiCarets.isEmpty {
            multiCarets = []
        }
        needsDisplay = true
    }

    private func multiTargets() -> [NSRange]? {
        if multiCarets.count > 1 { return multiCarets.map { NSRange(location: $0, length: 0) } }
        let ranges = selectedRanges.map { $0.rangeValue }
        return ranges.count > 1 ? ranges.sorted { $0.location < $1.location } : nil
    }

    private func multiInsert(_ targets: [NSRange], _ texts: [String]) {
        let inserted = applyEdits(Array(zip(targets, texts)))
        setMultiCarets(inserted.map { NSMaxRange($0) })
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if replacementRange.location == NSNotFound, let targets = multiTargets() {
            let s = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
            multiInsert(targets, Array(repeating: s, count: targets.count))
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        guard let targets = multiTargets() else { super.deleteBackward(sender); return }
        let edits: [(NSRange, String)] = targets.map { r in
            if r.length > 0 || r.location == 0 { return (r, "") }
            return (ns.rangeOfComposedCharacterSequence(at: r.location - 1), "")
        }
        let inserted = applyEdits(edits)
        setMultiCarets(inserted.map { $0.location })
    }

    override func deleteForward(_ sender: Any?) {
        guard let targets = multiTargets() else { super.deleteForward(sender); return }
        let length = ns.length
        let edits: [(NSRange, String)] = targets.map { r in
            if r.length > 0 || r.location >= length { return (r, "") }
            return (ns.rangeOfComposedCharacterSequence(at: r.location), "")
        }
        let inserted = applyEdits(edits)
        setMultiCarets(inserted.map { $0.location })
    }

    override func paste(_ sender: Any?) {
        if let targets = multiTargets(), let clip = NSPasteboard.general.string(forType: .string) {
            let normalized = LineEnding.normalize(clip)
            var lines = normalized.components(separatedBy: "\n")
            if lines.count == targets.count + 1, lines.last == "" { lines.removeLast() }
            if lines.count == targets.count {
                multiInsert(targets, lines)          // one line per cursor
            } else {
                multiInsert(targets, Array(repeating: normalized, count: targets.count))
            }
            return
        }
        super.paste(sender)
    }

    /// Esc collapses multiple cursors / selections.
    override func complete(_ sender: Any?) {
        if multiCarets.count > 1 || selectedRanges.count > 1 {
            let loc = multiCarets.last ?? selectedRange().location
            setSelectedRange(NSRange(location: loc, length: 0))
        }
    }

    func addCaret(below: Bool) {
        let carets = multiCarets.count > 1 ? multiCarets : [selectedRange().location]
        guard let ref = below ? carets.max() : carets.min() else { return }
        let text = ns
        let line = text.lineRange(for: NSRange(location: ref, length: 0))
        let column = ref - line.location
        var target: NSRange
        if below {
            let next = NSMaxRange(line)
            let lineHasNewline = line.length > 0 && text.character(at: NSMaxRange(line) - 1) == 10
            guard lineHasNewline else { NSSound.beep(); return }
            target = text.lineRange(for: NSRange(location: next, length: 0))
        } else {
            guard line.location > 0 else { NSSound.beep(); return }
            target = text.lineRange(for: NSRange(location: line.location - 1, length: 0))
        }
        var contentLength = target.length
        if contentLength > 0 && text.character(at: NSMaxRange(target) - 1) == 10 { contentLength -= 1 }
        let pos = target.location + min(column, contentLength)
        setMultiCarets(carets + [pos])
        scrollRangeToVisible(NSRange(location: pos, length: 0))
    }

    func addNextOccurrence() {
        var ranges = selectedRanges.map { $0.rangeValue }
        guard let first = ranges.first else { return }
        if first.length == 0 {
            let word = selectionRange(forProposedRange: first, granularity: .selectByWord)
            if word.length > 0 { setSelectedRange(word) }
            return
        }
        let needle = ns.substring(with: first)
        let maxEnd = ranges.map { NSMaxRange($0) }.max() ?? 0
        let minStart = ranges.map { $0.location }.min() ?? 0
        var found = ns.range(of: needle, options: [], range: NSRange(location: maxEnd, length: ns.length - maxEnd))
        if found.location == NSNotFound {
            found = ns.range(of: needle, options: [], range: NSRange(location: 0, length: minStart))
        }
        guard found.location != NSNotFound else { NSSound.beep(); return }
        ranges.append(found)
        selectedRanges = ranges.sorted { $0.location < $1.location }.map { NSValue(range: $0) }
        scrollRangeToVisible(found)
    }

    func selectAllOccurrences() {
        var sel = selectedRange()
        if sel.length == 0 {
            sel = selectionRange(forProposedRange: sel, granularity: .selectByWord)
            guard sel.length > 0 else { NSSound.beep(); return }
        }
        let needle = ns.substring(with: sel)
        var result: [NSValue] = []
        var searchRange = NSRange(location: 0, length: ns.length)
        while searchRange.length > 0 {
            let r = ns.range(of: needle, options: [], range: searchRange)
            if r.location == NSNotFound { break }
            result.append(NSValue(range: r))
            let next = NSMaxRange(r)
            searchRange = NSRange(location: next, length: ns.length - next)
        }
        if !result.isEmpty { selectedRanges = result }
    }

    // MARK: - Typing behaviour

    override func insertNewline(_ sender: Any?) {
        if multiTargets() != nil {
            insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
            return
        }
        if markdownMode && continueMarkdownBlock() { return }
        guard autoIndent else { super.insertNewline(sender); return }
        let sel = selectedRange()
        let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let beforeCursor = ns.substring(with: NSRange(location: line.location, length: sel.location - line.location))
        var indent = String(beforeCursor.prefix { $0 == " " || $0 == "\t" })
        let trimmed = beforeCursor.trimmingCharacters(in: .whitespaces)
        if let last = trimmed.last {
            if "{[(".contains(last) || (indentAfterColon && last == ":") {
                indent += indentUnit
            }
        }
        insertText("\n" + indent, replacementRange: sel)
    }

    override func insertTab(_ sender: Any?) {
        if multiTargets() != nil {
            insertText(indentUnit, replacementRange: NSRange(location: NSNotFound, length: 0))
            return
        }
        let sel = selectedRange()
        if sel.length > 0 && ns.substring(with: sel).contains("\n") {
            shiftLines(right: true)
            return
        }
        if useSpaces {
            let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            let column = sel.location - line.location
            let n = tabWidth - (column % tabWidth)
            insertText(String(repeating: " ", count: n), replacementRange: sel)
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        shiftLines(right: false)
    }

    // MARK: - Markdown helpers

    private static let mdListRE = try! NSRegularExpression(pattern: #"^(\s*)([-*+]|(\d+)([.)]))(\s+)(\[[ xX]\]\s+)?(.*)$"#)
    private static let mdQuoteRE = try! NSRegularExpression(pattern: #"^(\s*(?:>\s?)+)(.*)$"#)

    /// Enter inside a list item / blockquote continues it; Enter on an empty item ends the list.
    private func continueMarkdownBlock() -> Bool {
        let sel = selectedRange()
        guard sel.length == 0 else { return false }
        let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let before = ns.substring(with: NSRange(location: line.location, length: sel.location - line.location))
        let full = NSRange(location: 0, length: (before as NSString).length)
        let b = before as NSString

        if let m = EditorTextView.mdListRE.firstMatch(in: before, options: [], range: full) {
            func g(_ k: Int) -> String { m.range(at: k).location == NSNotFound ? "" : b.substring(with: m.range(at: k)) }
            let indent = g(1), spacing = g(5), checkbox = g(6), content = g(7)
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                // Empty item: remove the marker and stop the list
                replace(NSRange(location: line.location, length: sel.location - line.location), with: indent,
                        select: [NSRange(location: line.location + (indent as NSString).length, length: 0)])
                return true
            }
            var marker = g(2)
            if let n = Int(g(3)) { marker = "\(n + 1)" + g(4) }
            let box = checkbox.isEmpty ? "" : "[ ] "
            insertText("\n" + indent + marker + spacing + box, replacementRange: sel)
            return true
        }
        if let m = EditorTextView.mdQuoteRE.firstMatch(in: before, options: [], range: full) {
            let prefix = b.substring(with: m.range(at: 1))
            let content = b.substring(with: m.range(at: 2))
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                replace(NSRange(location: line.location, length: sel.location - line.location), with: "",
                        select: [NSRange(location: line.location, length: 0)])
                return true
            }
            insertText("\n" + prefix, replacementRange: sel)
            return true
        }
        return false
    }

    /// Wraps the selection in `prefix`/`suffix` (or unwraps it if already wrapped).
    func toggleWrap(prefix: String, suffix: String) {
        let sel = selectedRange()
        let p = (prefix as NSString).length, q = (suffix as NSString).length
        let text = ns
        if sel.length >= p + q {
            let selected = text.substring(with: sel)
            if selected.hasPrefix(prefix) && selected.hasSuffix(suffix) {
                let inner = (selected as NSString).substring(with: NSRange(location: p, length: sel.length - p - q))
                replace(sel, with: inner, select: [NSRange(location: sel.location, length: (inner as NSString).length)])
                return
            }
        }
        if sel.location >= p, NSMaxRange(sel) + q <= text.length,
           text.substring(with: NSRange(location: sel.location - p, length: p)) == prefix,
           text.substring(with: NSRange(location: NSMaxRange(sel), length: q)) == suffix {
            let outer = NSRange(location: sel.location - p, length: sel.length + p + q)
            let inner = text.substring(with: sel)
            replace(outer, with: inner, select: [NSRange(location: outer.location, length: sel.length)])
            return
        }
        let inner = text.substring(with: sel)
        replace(sel, with: prefix + inner + suffix, select: [NSRange(location: sel.location + p, length: sel.length)])
    }

    /// Turns the selection into [selection](url) and selects "url".
    func insertMarkdownLink() {
        let sel = selectedRange()
        let label = ns.substring(with: sel)
        var url = "url"
        if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           clip.hasPrefix("http://") || clip.hasPrefix("https://"), !clip.contains(" ") {
            url = clip
        }
        let text = "[\(label)](\(url))"
        let urlStart = sel.location + (label as NSString).length + 3
        replace(sel, with: text, select: [label.isEmpty
            ? NSRange(location: sel.location + 1, length: 0)
            : NSRange(location: urlStart, length: (url as NSString).length)])
    }

    // MARK: - Line operations

    /// Range of the full lines touched by the selection (a selection ending right after a newline
    /// does not include the following line).
    func selectedLinesRange() -> NSRange {
        var sel = selectedRange()
        if sel.length > 0, ns.character(at: NSMaxRange(sel) - 1) == 10 { sel.length -= 1 }
        return ns.lineRange(for: sel)
    }

    func shiftLines(right: Bool) {
        let lines = selectedLinesRange()
        let text = ns
        var edits: [(NSRange, String)] = []
        var loc = lines.location
        while loc < NSMaxRange(lines) {
            let line = text.lineRange(for: NSRange(location: loc, length: 0))
            if line.length == 0 { break }
            let isBlank = line.length == 1 && text.character(at: loc) == 10
            if right {
                if !isBlank { edits.append((NSRange(location: loc, length: 0), indentUnit)) }
            } else {
                var n = 0
                while n < tabWidth, loc + n < NSMaxRange(line), text.character(at: loc + n) == 32 { n += 1 }
                if n == 0, loc < NSMaxRange(line), text.character(at: loc) == 9 { n = 1 }
                if n > 0 { edits.append((NSRange(location: loc, length: n), "")) }
            }
            loc = NSMaxRange(line)
        }
        guard !edits.isEmpty else { return }
        let delta = edits.reduce(0) { $0 + ($1.1 as NSString).length - $1.0.length }
        applyEdits(edits)
        setSelectedRange(NSRange(location: lines.location, length: max(0, lines.length + delta)))
    }

    func duplicateLines() {
        let sel = selectedRange()
        let lines = selectedLinesRange()
        let block = ns.substring(with: lines)
        if block.hasSuffix("\n") {
            replace(NSRange(location: NSMaxRange(lines), length: 0), with: block)
        } else {
            replace(NSRange(location: NSMaxRange(lines), length: 0), with: "\n" + block)
        }
        let offset = (block as NSString).length + (block.hasSuffix("\n") ? 0 : 1)
        setSelectedRange(NSRange(location: sel.location + offset, length: sel.length))
    }

    func deleteLines() {
        var lines = selectedLinesRange()
        if lines.length == 0 { return }
        let endsWithNewline = ns.character(at: NSMaxRange(lines) - 1) == 10
        if !endsWithNewline && lines.location > 0 {
            lines = NSRange(location: lines.location - 1, length: lines.length + 1)
        }
        replace(lines, with: "", select: [NSRange(location: min(lines.location, ns.length - lines.length), length: 0)])
    }

    func moveLines(up: Bool) {
        let sel = selectedRange()
        let lines = selectedLinesRange()
        var block = ns.substring(with: lines)
        if up {
            guard lines.location > 0 else { NSSound.beep(); return }
            let prev = ns.lineRange(for: NSRange(location: lines.location - 1, length: 0))
            var prevText = ns.substring(with: prev)
            if !block.hasSuffix("\n") {
                block += "\n"
                prevText.removeLast()
            }
            replace(NSRange(location: prev.location, length: prev.length + lines.length), with: block + prevText)
            setSelectedRange(NSRange(location: sel.location - prev.length, length: sel.length))
        } else {
            guard NSMaxRange(lines) < ns.length else { NSSound.beep(); return }
            let next = ns.lineRange(for: NSRange(location: NSMaxRange(lines), length: 0))
            var nextText = ns.substring(with: next)
            if !nextText.hasSuffix("\n") {
                nextText += "\n"
                block.removeLast()
            }
            replace(NSRange(location: lines.location, length: lines.length + next.length), with: nextText + block)
            setSelectedRange(NSRange(location: sel.location + (nextText as NSString).length, length: sel.length))
        }
    }

    func toggleComment() {
        let lines = selectedLinesRange()
        let block = ns.substring(with: lines)
        let trailing = block.hasSuffix("\n")
        let body = trailing ? String(block.dropLast()) : block

        guard let token = lineComment else {
            guard let pair = blockComment else { NSSound.beep(); return }
            let (open, close) = pair
            let trimmed = body.trimmingCharacters(in: .whitespaces)
            var result: String
            if trimmed.hasPrefix(open) && trimmed.hasSuffix(close) && trimmed.count >= open.count + close.count {
                var inner = String(trimmed.dropFirst(open.count).dropLast(close.count))
                if inner.hasPrefix(" ") { inner.removeFirst() }
                if inner.hasSuffix(" ") { inner.removeLast() }
                let indent = String(body.prefix { $0 == " " || $0 == "\t" })
                result = indent + inner
            } else {
                let indent = String(body.prefix { $0 == " " || $0 == "\t" })
                let rest = String(body.dropFirst(indent.count))
                result = indent + open + " " + rest + " " + close
            }
            if trailing { result += "\n" }
            replace(lines, with: result, select: [NSRange(location: lines.location, length: (result as NSString).length)])
            return
        }

        let parts = body.components(separatedBy: "\n")
        let nonBlank = parts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonBlank.isEmpty else { return }
        let allCommented = nonBlank.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix(token) }
        let minIndent = nonBlank.map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
        let newParts = parts.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            if allCommented {
                guard let r = line.range(of: token) else { return line }
                var after = r.upperBound
                if after < line.endIndex && line[after] == " " { after = line.index(after: after) }
                return String(line[..<r.lowerBound]) + String(line[after...])
            } else {
                let idx = line.index(line.startIndex, offsetBy: minIndent)
                return String(line[..<idx]) + token + " " + String(line[idx...])
            }
        }
        var result = newParts.joined(separator: "\n")
        if trailing { result += "\n" }
        replace(lines, with: result, select: [NSRange(location: lines.location, length: (result as NSString).length)])
    }

    // MARK: - Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard highlightCurrentLine, selectedRanges.count == 1, multiCarets.isEmpty,
              let lm = layoutManager, let tc = textContainer else { return }
        let sel = selectedRange()
        guard sel.length == 0 else { return }
        let text = ns
        var lineRect: NSRect
        if sel.location >= text.length && (text.length == 0 || text.character(at: text.length - 1) == 10) {
            lineRect = lm.extraLineFragmentRect
        } else {
            let charRange = text.lineRange(for: NSRange(location: sel.location, length: 0))
            let glyphRange = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            lineRect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        }
        guard lineRect.height > 0 else { return }
        let r = NSRect(x: 0, y: lineRect.minY + textContainerOrigin.y, width: bounds.width, height: lineRect.height)
        Theme.currentLine.setFill()
        r.intersection(rect).fill()
    }

    private func caretRect(at location: Int) -> NSRect? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let text = ns
        let length = text.length
        let origin = textContainerOrigin
        if length == 0 || (location >= length && text.character(at: length - 1) == 10) {
            let r = lm.extraLineFragmentRect
            return NSRect(x: r.minX + tc.lineFragmentPadding + origin.x, y: r.minY + origin.y, width: 1.5, height: r.height)
        }
        let charIndex = min(location, length - 1)
        let glyphIndex = lm.glyphIndexForCharacter(at: charIndex)
        let glyphRect = lm.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: tc)
        let lineRect = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let x = location >= length ? glyphRect.maxX : glyphRect.minX
        return NSRect(x: x + origin.x, y: lineRect.minY + origin.y, width: 1.5, height: lineRect.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard multiCarets.count > 1 else { return }
        let primary = selectedRange().location
        insertionPointColor.setFill()
        for c in multiCarets where c != primary {
            if let r = caretRect(at: c), r.intersects(dirtyRect) { r.fill() }
        }
    }

    // MARK: - Drag & drop files onto the editor opens them

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        fileURLs(sender).isEmpty ? super.prepareForDragOperation(sender) : true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        if urls.isEmpty { return super.performDragOperation(sender) }
        onOpenFiles?(urls)
        return true
    }
}
