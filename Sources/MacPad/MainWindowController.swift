import AppKit

/// The single main window: tab bar, find bar, editor area and status bar. Owns all open documents.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate {
    private(set) var docs: [Document] = []
    private var currentIndex = -1
    var current: Document? { docs.indices.contains(currentIndex) ? docs[currentIndex] : nil }

    let tabBar = TabBarView()
    let findBar = FindBarView()
    let statusBar = StatusBarView()
    private let editorContainer = NSView()
    private let session = SessionStore()
    private var closedFiles: [URL] = []
    private var autosaveTimer: Timer?
    private lazy var findInFiles: FindInFilesController = makeFindInFiles()
    private var appearanceObservation: NSKeyValueObservation?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 520, height: 320)
        window.tabbingMode = .disallowed
        window.title = "roxy++"
        window.center()
        window.setFrameAutosaveName("MacPadMainWindow")
        super.init(window: window)
        window.delegate = self
        buildLayout()
        wireCallbacks()
        restoreSession()
        if docs.isEmpty { newDocument(nil) }
        // Terminal colors are fixed values, so refresh them when light/dark mode changes
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.docs.forEach { $0.terminal?.applyPreferences() } }
        }
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.saveSession()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    private func buildLayout() {
        guard let window else { return }
        let content = NSView()
        window.contentView = content

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        for view in [tabBar, findBar, editorContainer, statusBar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(view)
            view.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
        tabBar.heightAnchor.constraint(equalToConstant: 34).isActive = true
        statusBar.heightAnchor.constraint(equalToConstant: 24).isActive = true
        editorContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        editorContainer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        editorContainer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)
        for view in [tabBar, findBar, statusBar] as [NSView] {
            view.setContentHuggingPriority(.required, for: .vertical)
            view.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        findBar.isHidden = true
    }

    private func wireCallbacks() {
        tabBar.onSelect = { [weak self] id in
            guard let self, let i = self.docs.firstIndex(where: { $0.id == id }) else { return }
            self.select(index: i)
        }
        tabBar.onClose = { [weak self] id in
            guard let self, let doc = self.docs.first(where: { $0.id == id }) else { return }
            self.close(doc)
        }
        tabBar.onNew = { [weak self] in self?.newDocument(nil) }
        tabBar.onMove = { [weak self] from, to in
            guard let self, self.docs.indices.contains(from), self.docs.indices.contains(to) else { return }
            let selected = self.current
            let doc = self.docs.remove(at: from)
            self.docs.insert(doc, at: to)
            if let selected, let i = self.docs.firstIndex(where: { $0 === selected }) { self.currentIndex = i }
            self.refreshTabs()
        }
        tabBar.onContext = { [weak self] id, action in
            guard let self, let doc = self.docs.first(where: { $0.id == id }) else { return }
            switch action {
            case .close: self.close(doc)
            case .closeOthers: self.closeAll(except: doc)
            case .closeToRight:
                if let i = self.docs.firstIndex(where: { $0 === doc }) {
                    for other in self.docs[(i + 1)...].reversed() { if !self.close(other) { break } }
                }
            case .copyPath:
                if let url = doc.url {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
            case .revealInFinder:
                if let url = doc.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            case .openInTerminal:
                self.openTerminal(for: doc)
            case .newTerminalHere:
                self.newTerminal(in: self.terminalFolder(for: doc))
            }
        }

        findBar.onAction = { [weak self] action in self?.performFind(action) }

        statusBar.onLanguage = { [weak self] id in self?.setLanguage(id: id) }
        statusBar.onMarkdownMode = { [weak self] tag in
            let item = NSMenuItem()
            item.tag = tag
            self?.setMarkdownViewMode(item)
        }
        statusBar.onLineEnding = { [weak self] eol in self?.setLineEnding(eol) }
        statusBar.onEncoding = { [weak self] enc in self?.setEncoding(enc) }
    }

    private func makeFindInFiles() -> FindInFilesController {
        let c = FindInFilesController()
        c.onOpenHit = { [weak self] hit in
            guard let self else { return }
            self.open(urls: [hit.url])
            if let doc = self.docs.first(where: { $0.isSameFile(hit.url) }) {
                if let i = self.docs.firstIndex(where: { $0 === doc }) { self.select(index: i) }
                self.window?.makeKeyAndOrderFront(nil)
                doc.editor.goTo(line: hit.line, column: hit.column, length: hit.length)
            }
        }
        c.onReplaceInFiles = { [weak self] urls, options, replacement in
            self?.replaceInFiles(urls: urls, options: options, replacement: replacement) ?? ""
        }
        return c
    }

    // MARK: - Documents

    private func attach(_ doc: Document) {
        doc.editor.onTextChange = { [weak self, weak doc] in
            guard let self, let doc else { return }
            self.documentDidChange(doc)
        }
        doc.editor.onSelectionChange = { [weak self, weak doc] in
            guard let self, let doc, doc === self.current else { return }
            self.refreshStatus()
        }
        doc.editor.textView.onOpenFiles = { [weak self] urls in self?.open(urls: urls) }
        doc.editor.onViewModeChange = { [weak self, weak doc] in
            guard let self, let doc, doc === self.current else { return }
            self.refreshStatus()
        }
        doc.editor.previewBaseURL = doc.url?.deletingLastPathComponent()
    }

    private func documentDidChange(_ doc: Document) {
        doc.changeCount += 1
        if !doc.isDirty {
            doc.isDirty = true
            refreshTabs()
            refreshTitle()
        }
        if doc === current { refreshStatus() }
    }

    func select(index: Int) {
        guard docs.indices.contains(index) else { return }
        if let old = current, old !== docs[index] { old.contentView.removeFromSuperview() }
        currentIndex = index
        let doc = docs[index]
        let editor = doc.editor
        let content = doc.contentView
        if content.superview !== editorContainer {
            content.frame = editorContainer.bounds
            content.autoresizingMask = [.width, .height]
            editorContainer.addSubview(content)
        }
        if doc.isTerminal { findBar.isHidden = true }
        focusCurrent()
        if !doc.isTerminal, let pending = doc.pendingSelection {
            doc.pendingSelection = nil
            DispatchQueue.main.async {
                let length = (editor.textView.string as NSString).length
                let range = NSRange(location: min(pending, length), length: 0)
                editor.textView.setSelectedRange(range)
                editor.textView.scrollRangeToVisible(range)
            }
        }
        refreshTabs()
        refreshTitle()
        refreshStatus()
    }

    private func focusCurrent() {
        guard let doc = current else { return }
        if let terminal = doc.terminal {
            window?.makeFirstResponder(terminal.view)
        } else {
            doc.editor.focus()
        }
    }

    private func nextUntitledIndex() -> Int {
        let used = Set(docs.filter { $0.url == nil && !$0.isTerminal }.map { $0.untitledIndex })
        var n = 1
        while used.contains(n) { n += 1 }
        return n
    }

    @objc func newDocument(_ sender: Any?) {
        let doc = Document(url: nil, untitledIndex: nextUntitledIndex(), text: "", language: .plain)
        attach(doc)
        docs.append(doc)
        select(index: docs.count - 1)
    }

    // MARK: - Terminal tabs

    @objc func newTerminalTab(_ sender: Any?) { newTerminal(in: terminalFolder(for: current)) }

    /// Folder of the file in `doc`; for terminal tabs, their current folder.
    private func terminalFolder(for doc: Document?) -> URL? {
        if let terminal = doc?.terminal { return URL(fileURLWithPath: terminal.directory) }
        return doc?.url?.deletingLastPathComponent()
    }

    func newTerminal(in directory: URL?) {
        let doc = Document(terminalIn: directory)
        doc.terminal?.onTitleChange = { [weak self, weak doc] in
            guard let self, let doc else { return }
            self.refreshTabs()
            if doc === self.current { self.refreshTitle(); self.refreshStatus() }
        }
        doc.terminal?.onExit = { [weak self, weak doc] in
            guard let self, let doc, self.docs.contains(where: { $0 === doc }) else { return }
            self.close(doc)
        }
        if let i = docs.firstIndex(where: { $0 === current }) {
            docs.insert(doc, at: i + 1)
            select(index: i + 1)
        } else {
            docs.append(doc)
            select(index: docs.count - 1)
        }
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let dir = current?.url?.deletingLastPathComponent() { panel.directoryURL = dir }
        guard panel.runModal() == .OK else { return }
        open(urls: panel.urls)
    }

    func open(urls: [URL]) {
        var lastIndex: Int?
        for raw in urls {
            let url = raw.standardizedFileURL.resolvingSymlinksInPath()
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                showAlert("“\(url.lastPathComponent)” doesn't exist.", info: url.path)
                continue
            }
            if isDir.boolValue {
                findInFiles.present(directory: url, query: nil)
                continue
            }
            if let i = docs.firstIndex(where: { $0.isSameFile(url) }) {
                lastIndex = i
                continue
            }
            do {
                let loaded = try FileIO.load(url)
                let doc = Document(url: url, untitledIndex: 0, text: loaded.text,
                                   encoding: loaded.encoding, lineEnding: loaded.lineEnding,
                                   language: Language.detect(url: url, text: loaded.text))
                doc.fileModificationDate = FileIO.modificationDate(url)
                // Replace a single pristine "new 1" tab, like Notepad++
                if docs.count == 1, let only = docs.first, only.url == nil, !only.isTerminal, !only.isDirty, only.text.isEmpty {
                    only.editor.removeFromSuperview()
                    docs.removeAll()
                    currentIndex = -1
                }
                attach(doc)
                applyMarkdownOpenMode(doc)
                docs.append(doc)
                lastIndex = docs.count - 1
                RecentFiles.add(url)
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            } catch {
                showAlert("Couldn't open “\(url.lastPathComponent)”.", info: error.localizedDescription)
            }
        }
        if let i = lastIndex { select(index: i) }
    }

    @discardableResult
    func save(_ doc: Document) -> Bool {
        guard let url = doc.url else { return saveAs(doc) }
        return write(doc, to: url)
    }

    @discardableResult
    func saveAs(_ doc: Document) -> Bool {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = doc.url?.lastPathComponent ?? "\(doc.displayName).txt"
        if let dir = doc.url?.deletingLastPathComponent() { panel.directoryURL = dir }
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let wasPlain = doc.editor.language.id == Language.plain.id
        guard write(doc, to: url) else { return false }
        if wasPlain { doc.editor.language = Language.detect(url: url, text: doc.text) }
        RecentFiles.add(url)
        refreshAll()
        return true
    }

    private func write(_ doc: Document, to url: URL) -> Bool {
        do {
            try doc.write(to: url)
            doc.editor.previewBaseURL = url.deletingLastPathComponent()
        } catch let error as EncodeError {
            let alert = NSAlert()
            alert.messageText = "Can't save “\(doc.displayName)” as \(error.encoding.label)."
            alert.informativeText = (error.errorDescription ?? "") + " Save it as UTF-8 instead?"
            alert.addButton(withTitle: "Save as UTF-8")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            doc.encoding = .utf8
            return write(doc, to: url)
        } catch {
            showAlert("Couldn't save “\(url.lastPathComponent)”.", info: error.localizedDescription)
            return false
        }
        refreshAll()
        return true
    }

    /// Closes a tab, asking to save if needed. Returns false if the user cancelled.
    @discardableResult
    func close(_ doc: Document) -> Bool {
        if doc.isDirty {
            if let i = docs.firstIndex(where: { $0 === doc }) { select(index: i) }
            let alert = NSAlert()
            alert.messageText = "Save changes to “\(doc.displayName)”?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                if !save(doc) { return false }
            case .alertSecondButtonReturn:
                break
            default:
                return false
            }
        }
        if let terminal = doc.terminal, terminal.hasRunningCommand {
            if let i = docs.firstIndex(where: { $0 === doc }) { select(index: i) }
            let alert = NSAlert()
            alert.messageText = "Close this terminal?"
            alert.informativeText = "A command is still running in it. Closing the tab will stop it."
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        guard let idx = docs.firstIndex(where: { $0 === doc }) else { return false }
        if let url = doc.url { closedFiles.append(url) }
        doc.contentView.removeFromSuperview()
        doc.terminal?.onExit = nil
        doc.terminal?.terminate()
        docs.remove(at: idx)
        if docs.isEmpty {
            currentIndex = -1
            newDocument(nil)
        } else if idx == currentIndex {
            currentIndex = -1
            select(index: min(idx, docs.count - 1))
        } else {
            if idx < currentIndex { currentIndex -= 1 }
            refreshTabs()
        }
        return true
    }

    func closeAll(except keep: Document? = nil) {
        for doc in docs.reversed() where doc !== keep {
            if !close(doc) { return }
        }
    }

    // MARK: - External changes

    func checkExternalChanges() {
        for doc in docs {
            guard let url = doc.url, let known = doc.fileModificationDate,
                  let now = FileIO.modificationDate(url), now.timeIntervalSince(known) > 0.5 else { continue }
            doc.fileModificationDate = now
            if doc.isDirty {
                if let i = docs.firstIndex(where: { $0 === doc }) { select(index: i) }
                let alert = NSAlert()
                alert.messageText = "“\(doc.displayName)” was changed by another application."
                alert.informativeText = "Reload it and lose your unsaved changes in roxy++?"
                alert.addButton(withTitle: "Reload")
                alert.addButton(withTitle: "Keep My Version")
                guard alert.runModal() == .alertFirstButtonReturn else { continue }
            }
            reload(doc)
        }
    }

    private func reload(_ doc: Document, encoding: FileEncoding? = nil) {
        guard let url = doc.url else { return }
        do {
            let text: String
            let enc: FileEncoding
            let eol: LineEnding
            if let encoding {
                let data = try Data(contentsOf: url)
                guard let decoded = FileIO.decode(data, as: encoding) else {
                    showAlert("The file can't be read as \(encoding.label).", info: url.path)
                    return
                }
                text = LineEnding.normalize(decoded)
                enc = encoding
                eol = LineEnding.detect(in: decoded)
            } else {
                let loaded = try FileIO.load(url)
                text = loaded.text
                enc = loaded.encoding
                eol = loaded.lineEnding
            }
            if text != doc.text { doc.editor.replaceAllText(with: text) }
            doc.encoding = enc
            doc.lineEnding = eol
            doc.isDirty = false
            doc.fileModificationDate = FileIO.modificationDate(url)
            refreshAll()
        } catch {
            showAlert("Couldn't reload “\(url.lastPathComponent)”.", info: error.localizedDescription)
        }
    }

    // MARK: - Session

    func saveSession() {
        // Terminal tabs aren't restored after a restart
        let saved = docs.filter { !$0.isTerminal }
        let selected = current.flatMap { cur in saved.firstIndex(where: { $0 === cur }) } ?? 0
        session.save(docs: saved, selectedIndex: selected)
    }

    private func restoreSession() {
        guard let data = session.load() else { return }
        for tab in data.tabs {
            let url = tab.path.map { URL(fileURLWithPath: $0) }
            var text: String?
            var encoding = tab.encoding
            var lineEnding = tab.lineEnding
            var dirty = false
            if tab.hasBackup, let backup = session.backup(for: tab.id) {
                text = backup
                dirty = tab.dirty
            } else if let url {
                guard let loaded = try? FileIO.load(url) else { continue } // file is gone
                text = loaded.text
                encoding = loaded.encoding
                lineEnding = loaded.lineEnding
            } else {
                text = ""
            }
            let doc = Document(id: tab.id, url: url, untitledIndex: tab.untitledIndex, text: text ?? "",
                               encoding: encoding, lineEnding: lineEnding, language: Language.byID(tab.language))
            doc.isDirty = dirty
            doc.fileModificationDate = dirty ? tab.modificationDate : (url.flatMap { FileIO.modificationDate($0) })
            doc.pendingSelection = tab.selection
            if dirty { doc.backedUpChangeCount = doc.changeCount }
            attach(doc)
            applyMarkdownOpenMode(doc)
            docs.append(doc)
        }
        if !docs.isEmpty {
            select(index: min(max(0, data.selected), docs.count - 1))
        }
    }

    // MARK: - UI refresh

    func refreshAll() {
        refreshTabs()
        refreshTitle()
        refreshStatus()
    }

    func refreshTabs() {
        tabBar.items = docs.map {
            TabBarView.Item(id: $0.id, title: $0.displayName, dirty: $0.isDirty,
                            tooltip: $0.terminal?.directory ?? $0.url?.path ?? $0.displayName)
        }
        tabBar.selectedID = current?.id
    }

    func refreshTitle() {
        guard let window else { return }
        guard let doc = current else { window.title = "roxy++"; return }
        window.title = doc.displayName
        if let terminal = doc.terminal {
            window.subtitle = terminal.title.isEmpty ? (terminal.directory as NSString).abbreviatingWithTildeInPath : terminal.title
            window.representedURL = nil
            window.isDocumentEdited = false
            return
        }
        window.subtitle = doc.url?.deletingLastPathComponent().path ?? ""
        window.representedURL = doc.url
        window.isDocumentEdited = doc.isDirty
    }

    func refreshStatus() {
        guard let doc = current else { return }
        statusBar.setTerminalMode(doc.isTerminal)
        if let terminal = doc.terminal {
            statusBar.positionLabel.stringValue = "Terminal"
            statusBar.infoLabel.stringValue = (terminal.directory as NSString).abbreviatingWithTildeInPath
            statusBar.setMarkdownMode(nil)
            return
        }
        let tv = doc.editor.textView
        let (line, column) = doc.editor.caretPosition()
        let selections = tv.selectedRanges.map { $0.rangeValue }
        let selected = selections.reduce(0) { $0 + $1.length }
        var position = "Ln \(line), Col \(column)"
        if selected > 0 { position += "   Sel \(selected)" + (selections.count > 1 ? " (\(selections.count) ranges)" : "") }
        let length = (tv.string as NSString).length
        let info = "\(doc.editor.lineIndex.count) lines   \(length) chars"
        statusBar.update(position: position, info: info, languageID: doc.editor.language.id,
                         lineEnding: doc.lineEnding, encoding: doc.encoding)
        let modeTags: [EditorView.ViewMode: Int] = [.source: 1, .split: 2, .rendered: 3]
        let isMarkdown = doc.editor.language.id == "markdown" || doc.editor.viewMode != .source
        statusBar.setMarkdownMode(isMarkdown ? modeTags[doc.editor.viewMode] : nil)
    }

    private func showAlert(_ message: String, info: String = "") {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.runModal()
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        saveSession()
        NSApp.terminate(nil)
        return false
    }

    // MARK: - File menu actions

    @objc func saveDocument(_ sender: Any?) {
        guard let doc = current, !doc.isTerminal else { return }
        doc.editor.flushRenderedEdits { [weak self] in self?.save(doc) }
    }
    @objc func saveDocumentAs(_ sender: Any?) {
        guard let doc = current, !doc.isTerminal else { return }
        doc.editor.flushRenderedEdits { [weak self] in self?.saveAs(doc) }
    }
    @objc func saveAllDocuments(_ sender: Any?) {
        for doc in docs where doc.isDirty {
            if let i = docs.firstIndex(where: { $0 === doc }) { select(index: i) }
            if !save(doc) { return }
        }
    }
    @objc func reloadFromDisk(_ sender: Any?) {
        guard let doc = current else { return }
        if doc.isDirty {
            let alert = NSAlert()
            alert.messageText = "Reload “\(doc.displayName)” from disk?"
            alert.informativeText = "Your unsaved changes will be lost (you can still undo)."
            alert.addButton(withTitle: "Reload")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        reload(doc)
    }
    @objc func closeTab(_ sender: Any?) {
        if let sheetParent = NSApp.keyWindow, sheetParent !== window {
            sheetParent.performClose(sender)
            return
        }
        if let doc = current { close(doc) }
    }
    @objc func closeAllTabs(_ sender: Any?) { closeAll() }
    @objc func closeOtherTabs(_ sender: Any?) { closeAll(except: current) }
    @objc func reopenClosedTab(_ sender: Any?) {
        while let url = closedFiles.popLast() {
            if FileManager.default.fileExists(atPath: url.path) { open(urls: [url]); return }
        }
        NSSound.beep()
    }
    @objc func revealInFinder(_ sender: Any?) {
        if let url = current?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    @objc func openInTerminal(_ sender: Any?) { openTerminal(for: current) }

    /// Opens macOS Terminal in the document's folder (home folder for unsaved tabs).
    func openTerminal(for doc: Document?) {
        let folder = terminalFolder(for: doc) ?? FileManager.default.homeDirectoryForCurrentUser
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            showAlert("Couldn't find the Terminal app.")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: config) { _, error in
            if let error {
                DispatchQueue.main.async { self.showAlert("Couldn't open Terminal.", info: error.localizedDescription) }
            }
        }
    }

    @objc func copyFilePath(_ sender: Any?) {
        guard let url = current?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
    @objc func openRecent(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        open(urls: [URL(fileURLWithPath: path)])
    }
    @objc func clearRecent(_ sender: Any?) { RecentFiles.clear() }

    // MARK: - Edit actions

    /// The current tab's text view (nil for terminal tabs).
    private var tv: EditorTextView? {
        guard let doc = current, !doc.isTerminal else { return nil }
        return doc.editor.textView
    }

    /// Current tab if it's a text document (not a terminal).
    private var currentTextDoc: Document? {
        guard let doc = current, !doc.isTerminal else { return nil }
        return doc
    }

    /// Undo manager of whatever has keyboard focus (a tab's editor has its own; text fields use the window's).
    private var activeUndoManager: UndoManager? {
        if let responder = NSApp.keyWindow?.firstResponder {
            if let editor = responder as? EditorTextView { return editor.undoManager }
            return responder.undoManager
        }
        return tv?.undoManager
    }

    @objc func undoAction(_ sender: Any?) {
        if let editor = current?.editor, editor.renderedHasFocus, NSApp.keyWindow === window {
            editor.runRenderedCommand("undo")
            return
        }
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.breakUndoCoalescing()
        activeUndoManager?.undo()
    }

    @objc func redoAction(_ sender: Any?) {
        if let editor = current?.editor, editor.renderedHasFocus, NSApp.keyWindow === window {
            editor.runRenderedCommand("redo")
            return
        }
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.breakUndoCoalescing()
        activeUndoManager?.redo()
    }

    @objc func duplicateLine(_ sender: Any?) { tv?.duplicateLines() }
    @objc func deleteLine(_ sender: Any?) { tv?.deleteLines() }
    @objc func moveLineUp(_ sender: Any?) { tv?.moveLines(up: true) }
    @objc func moveLineDown(_ sender: Any?) { tv?.moveLines(up: false) }
    @objc func toggleComment(_ sender: Any?) { tv?.toggleComment() }
    @objc func indentLines(_ sender: Any?) { tv?.shiftLines(right: true) }
    @objc func outdentLines(_ sender: Any?) { tv?.shiftLines(right: false) }
    @objc func selectAllOccurrences(_ sender: Any?) { tv?.selectAllOccurrences() }
    @objc func addNextOccurrence(_ sender: Any?) { tv?.addNextOccurrence() }
    @objc func addCaretAbove(_ sender: Any?) { tv?.addCaret(below: false) }
    @objc func addCaretBelow(_ sender: Any?) { tv?.addCaret(below: true) }

    @objc func insertDateTime(_ sender: Any?) {
        guard let tv else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        tv.insertText(f.string(from: Date()), replacementRange: tv.selectedRange())
    }

    @objc func goToLine(_ sender: Any?) {
        guard let doc = currentTextDoc else { return }
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        alert.informativeText = "Line number (1 – \(doc.editor.lineIndex.count)), optionally followed by :column"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "e.g. 120 or 120:8"
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let parts = field.stringValue.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = parts.first, let line = Int(first) else { return }
        let column = parts.count > 1 ? max(0, (Int(parts[1]) ?? 1) - 1) : 0
        doc.editor.goTo(line: line, column: column)
    }

    // MARK: - Text tools

    @objc func textTool(_ sender: NSMenuItem) {
        guard let tool = TextTool(rawValue: sender.tag), let tv else { return }
        let sel = tv.selectedRange()
        let wholeDocument = sel.length == 0
        let range = wholeDocument ? NSRange(location: 0, length: tv.ns.length)
                                  : (tool.lineBased ? tv.selectedLinesRange() : sel)
        let input = tv.ns.substring(with: range)
        do {
            let output = try TextTools.apply(tool, to: input, tabWidth: Prefs.tabWidth)
            guard output != input else { return }
            let outLength = (output as NSString).length
            let newSelection = wholeDocument ? NSRange(location: min(sel.location, outLength), length: 0)
                                             : NSRange(location: range.location, length: outLength)
            tv.replace(range, with: output, select: [newSelection])
        } catch {
            showAlert(error.localizedDescription)
        }
    }

    // MARK: - Find

    @objc func showFind(_ sender: Any?) { presentFindBar(replace: false) }
    @objc func showReplace(_ sender: Any?) { presentFindBar(replace: true) }
    @objc func findNextAction(_ sender: Any?) { performFind(.next) }
    @objc func findPreviousAction(_ sender: Any?) { performFind(.previous) }
    @objc func markAllAction(_ sender: Any?) { performFind(.markAll) }
    @objc func clearMarks(_ sender: Any?) { current?.editor.clearMarks() }

    @objc func useSelectionForFind(_ sender: Any?) {
        guard let tv else { return }
        let sel = tv.selectedRange()
        guard sel.length > 0 else { return }
        findBar.findField.stringValue = tv.ns.substring(with: sel)
    }

    @objc func showFindInFiles(_ sender: Any?) {
        var query: String? = findBar.findField.stringValue
        if let tv, tv.selectedRange().length > 0, tv.selectedRange().length < 300 {
            let s = tv.ns.substring(with: tv.selectedRange())
            if !s.contains("\n") { query = s }
        }
        findInFiles.present(directory: terminalFolder(for: current), query: query)
    }

    private func presentFindBar(replace: Bool) {
        guard currentTextDoc != nil else { NSSound.beep(); return }
        findBar.showsReplace = replace
        findBar.isHidden = false
        if let tv {
            let sel = tv.selectedRange()
            if sel.length > 0 && sel.length < 500 {
                let s = tv.ns.substring(with: sel)
                if !s.contains("\n") { findBar.findField.stringValue = s }
            }
        }
        window?.makeFirstResponder(findBar.findField)
        findBar.findField.selectText(nil)
    }

    private func hideFindBar() {
        findBar.isHidden = true
        focusCurrent()
    }

    func performFind(_ action: FindBarView.Action) {
        if action == .close { hideFindBar(); return }
        if action == .findInFiles { showFindInFiles(nil); return }
        guard let doc = currentTextDoc else { return }
        let tv = doc.editor.textView
        let options = findBar.options
        guard !options.query.isEmpty else {
            if findBar.isHidden { presentFindBar(replace: false) }
            findBar.setStatus("")
            return
        }
        let regex: NSRegularExpression
        do { regex = try SearchEngine.regex(options) } catch {
            findBar.setStatus("Invalid regular expression", isError: true)
            NSSound.beep()
            return
        }
        let text = tv.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        let template = SearchEngine.template(findBar.replacement, regex: options.regex)

        if doc.editor.isRendered && (action == .next || action == .previous) {
            doc.editor.findInRendered(options.query, backwards: action == .previous,
                                      caseSensitive: options.caseSensitive, wraps: options.wrap) { [weak self] found in
                self?.findBar.setStatus(found ? "" : "Not found", isError: !found)
                if !found { NSSound.beep() }
            }
            return
        }

        switch action {
        case .next, .previous:
            let sel = tv.selectedRange()
            let found = action == .next
                ? SearchEngine.findNext(in: text, from: NSMaxRange(sel), regex: regex, wrap: options.wrap)
                : SearchEngine.findPrevious(in: text, before: sel.location, regex: regex, wrap: options.wrap)
            if let found {
                tv.setSelectedRange(found.range)
                tv.scrollRangeToVisible(found.range)
                tv.showFindIndicator(for: found.range)
                findBar.setStatus(found.wrapped ? "Wrapped around" : "")
            } else {
                findBar.setStatus("Not found", isError: true)
                NSSound.beep()
            }
        case .count:
            let n = regex.numberOfMatches(in: text, options: [], range: full)
            findBar.setStatus("\(n) match\(n == 1 ? "" : "es")")
        case .markAll:
            let ranges = regex.matches(in: text, options: [], range: full).map { $0.range }.filter { $0.length > 0 }
            doc.editor.mark(ranges)
            findBar.setStatus("Marked \(ranges.count) match\(ranges.count == 1 ? "" : "es") (Find ▸ Clear Marks to remove)")
        case .replace:
            let sel = tv.selectedRange()
            if let m = regex.firstMatch(in: text, options: .anchored, range: sel), m.range == sel {
                let replacement = regex.replacementString(for: m, in: text, offset: 0, template: template)
                tv.replace(sel, with: replacement,
                           select: [NSRange(location: sel.location + (replacement as NSString).length, length: 0)])
            }
            performFind(.next)
        case .replaceAll:
            let matches = regex.matches(in: text, options: [], range: full)
            guard !matches.isEmpty else { findBar.setStatus("Not found", isError: true); return }
            let edits = matches.map { m in (m.range, regex.replacementString(for: m, in: text, offset: 0, template: template)) }
            tv.applyEdits(edits)
            findBar.setStatus("Replaced \(matches.count) occurrence\(matches.count == 1 ? "" : "s")")
        case .findInFiles, .close:
            break
        }
    }

    func replaceInFiles(urls: [URL], options: SearchOptions, replacement: String) -> String {
        guard let regex = try? SearchEngine.regex(options) else { return "Invalid regular expression." }
        let template = SearchEngine.template(replacement, regex: options.regex)
        var files = 0
        var count = 0
        var errors: [String] = []
        for url in urls {
            if let doc = docs.first(where: { $0.isSameFile(url) }) {
                let text = doc.text
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length))
                guard !matches.isEmpty else { continue }
                doc.editor.textView.applyEdits(matches.map { ($0.range, regex.replacementString(for: $0, in: text, offset: 0, template: template)) })
                files += 1
                count += matches.count
            } else {
                do {
                    let loaded = try FileIO.load(url)
                    let full = NSRange(location: 0, length: (loaded.text as NSString).length)
                    let n = regex.numberOfMatches(in: loaded.text, options: [], range: full)
                    guard n > 0 else { continue }
                    let newText = regex.stringByReplacingMatches(in: loaded.text, options: [], range: full, withTemplate: template)
                    let data = try FileIO.encode(newText, encoding: loaded.encoding, lineEnding: loaded.lineEnding)
                    try data.write(to: url, options: .atomic)
                    files += 1
                    count += n
                } catch {
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        var summary = "Replaced \(count) occurrence\(count == 1 ? "" : "s") in \(files) file\(files == 1 ? "" : "s")."
        if !errors.isEmpty { summary += " Errors: " + errors.joined(separator: "; ") }
        return summary
    }

    // MARK: - View

    private func applyPreferencesToAll() {
        for doc in docs {
            doc.editor.applyPreferences()
            doc.terminal?.applyPreferences()
        }
    }

    @objc func toggleWordWrap(_ sender: Any?) { Prefs.wordWrap.toggle(); applyPreferencesToAll() }
    @objc func toggleLineNumbers(_ sender: Any?) { Prefs.showLineNumbers.toggle(); applyPreferencesToAll() }
    @objc func toggleCurrentLine(_ sender: Any?) { Prefs.highlightCurrentLine.toggle(); applyPreferencesToAll() }
    @objc func toggleInvisibles(_ sender: Any?) { Prefs.showInvisibles.toggle(); applyPreferencesToAll() }
    @objc func toggleUseSpaces(_ sender: Any?) { Prefs.useSpaces.toggle(); applyPreferencesToAll() }
    @objc func toggleAutoIndent(_ sender: Any?) { Prefs.autoIndent.toggle(); applyPreferencesToAll() }
    @objc func setTabWidth(_ sender: NSMenuItem) { Prefs.tabWidth = sender.tag; applyPreferencesToAll() }
    @objc func zoomIn(_ sender: Any?) { Prefs.fontSize += 1; applyPreferencesToAll() }
    @objc func zoomOut(_ sender: Any?) { Prefs.fontSize -= 1; applyPreferencesToAll() }
    @objc func zoomReset(_ sender: Any?) { Prefs.fontSize = 13; applyPreferencesToAll() }

    /// View ▸ Appearance: represented object = "system" / "light" / "dark"
    @objc func setAppearance(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? String { Prefs.appearance = mode }
    }

    @objc func setLanguageFromMenu(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { setLanguage(id: id) }
    }

    func setLanguage(id: String) {
        guard let doc = currentTextDoc else { return }
        doc.editor.language = Language.byID(id)
        refreshStatus()
    }

    // MARK: - Markdown

    private func applyMarkdownOpenMode(_ doc: Document) {
        guard doc.editor.language.id == "markdown",
              let mode = EditorView.ViewMode(rawValue: Prefs.markdownOpenMode), mode != .source else { return }
        doc.editor.setViewMode(mode)
    }

    @objc func toggleMarkdownPreview(_ sender: Any?) {
        guard let doc = currentTextDoc else { return }
        doc.editor.previewBaseURL = doc.url?.deletingLastPathComponent()
        doc.editor.setViewMode(doc.editor.isPreviewVisible ? .source : .split)
        DispatchQueue.main.async { [weak self] in self?.refreshStatus() }
    }

    /// Markdown ▸ View: tag 1 = source, 2 = split, 3 = rendered (editable)
    @objc func setMarkdownViewMode(_ sender: NSMenuItem) {
        guard let doc = currentTextDoc else { return }
        let modes: [Int: EditorView.ViewMode] = [1: .source, 2: .split, 3: .rendered]
        guard let mode = modes[sender.tag] else { return }
        doc.editor.previewBaseURL = doc.url?.deletingLastPathComponent()
        doc.editor.setViewMode(mode)
        DispatchQueue.main.async { [weak self] in self?.refreshStatus() }
    }

    /// Markdown ▸ Open Markdown Files In: represented object = mode raw value
    @objc func setMarkdownOpenMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String { Prefs.markdownOpenMode = raw }
    }

    private func markdownCommand(_ rendered: String, source: (EditorTextView) -> Void) {
        guard let doc = currentTextDoc else { return }
        if doc.editor.isRendered {
            doc.editor.runRenderedCommand(rendered)
        } else {
            source(doc.editor.textView)
        }
    }

    @objc func markdownBold(_ sender: Any?) { markdownCommand("bold") { $0.toggleWrap(prefix: "**", suffix: "**") } }
    @objc func markdownItalic(_ sender: Any?) { markdownCommand("italic") { $0.toggleWrap(prefix: "*", suffix: "*") } }
    @objc func markdownStrikethrough(_ sender: Any?) { markdownCommand("strike") { $0.toggleWrap(prefix: "~~", suffix: "~~") } }
    @objc func markdownLink(_ sender: Any?) { markdownCommand("link") { $0.insertMarkdownLink() } }
    @objc func markdownCode(_ sender: Any?) {
        markdownCommand("code") { tv in
            let sel = tv.selectedRange()
            if sel.length > 0 && tv.ns.substring(with: sel).contains("\n") {
                tv.toggleWrap(prefix: "```\n", suffix: "\n```")
            } else {
                tv.toggleWrap(prefix: "`", suffix: "`")
            }
        }
    }
    @objc func markdownHeading(_ sender: NSMenuItem) {
        markdownCommand(sender.tag == 0 ? "p" : "h\(sender.tag)") { tv in
            let lines = tv.selectedLinesRange()
            var line = tv.ns.substring(with: lines)
            let trailing = line.hasSuffix("\n")
            if trailing { line.removeLast() }
            let stripped = String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            var result = sender.tag == 0 ? stripped : String(repeating: "#", count: sender.tag) + " " + stripped
            if trailing { result += "\n" }
            tv.replace(lines, with: result, select: [NSRange(location: lines.location + (result as NSString).length - (trailing ? 1 : 0), length: 0)])
        }
    }

    @objc func exportHTML(_ sender: Any?) {
        guard let doc = currentTextDoc else { return }
        let panel = NSSavePanel()
        let baseName = doc.url?.deletingPathExtension().lastPathComponent ?? doc.displayName
        panel.nameFieldStringValue = baseName + ".html"
        panel.canCreateDirectories = true
        if let dir = doc.url?.deletingLastPathComponent() { panel.directoryURL = dir }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let body = Markdown.toHTML(doc.text, baseURL: doc.url?.deletingLastPathComponent())
        let html = Markdown.page(body: body, title: baseName, interactive: false)
        do {
            try Data(html.utf8).write(to: url, options: .atomic)
        } catch {
            showAlert("Couldn't export “\(url.lastPathComponent)”.", info: error.localizedDescription)
        }
    }

    @objc func copyAsHTML(_ sender: Any?) {
        guard let tv else { return }
        let sel = tv.selectedRange()
        let source = sel.length > 0 ? tv.ns.substring(with: sel) : tv.string
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Markdown.toHTML(source, baseURL: current?.url?.deletingLastPathComponent()), forType: .string)
    }

    // MARK: - Encoding / line endings

    func setEncoding(_ encoding: FileEncoding) {
        guard let doc = currentTextDoc, doc.encoding != encoding else { return }
        doc.encoding = encoding
        doc.isDirty = true
        doc.changeCount += 1
        refreshAll()
    }

    func setLineEnding(_ lineEnding: LineEnding) {
        guard let doc = currentTextDoc, doc.lineEnding != lineEnding else { return }
        doc.lineEnding = lineEnding
        doc.isDirty = true
        doc.changeCount += 1
        refreshAll()
    }

    @objc func convertEncodingFromMenu(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let enc = FileEncoding(rawValue: raw) { setEncoding(enc) }
    }

    @objc func reopenWithEncoding(_ sender: NSMenuItem) {
        guard let doc = currentTextDoc, let raw = sender.representedObject as? String,
              let enc = FileEncoding(rawValue: raw) else { return }
        if doc.isDirty {
            let alert = NSAlert()
            alert.messageText = "Reopen “\(doc.displayName)” as \(enc.label)?"
            alert.informativeText = "Unsaved changes will be replaced by the file's contents (you can still undo)."
            alert.addButton(withTitle: "Reopen")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        reload(doc, encoding: enc)
    }

    @objc func setLineEndingFromMenu(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let eol = LineEnding(rawValue: raw) { setLineEnding(eol) }
    }

    // MARK: - Tabs

    @objc func nextTab(_ sender: Any?) {
        guard docs.count > 1 else { return }
        select(index: (currentIndex + 1) % docs.count)
    }
    @objc func previousTab(_ sender: Any?) {
        guard docs.count > 1 else { return }
        select(index: (currentIndex - 1 + docs.count) % docs.count)
    }
    @objc func selectTabNumber(_ sender: NSMenuItem) {
        let i = sender.tag == 9 ? docs.count - 1 : sender.tag - 1
        select(index: i)
    }

    // MARK: - Menu validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let action = item.action else { return true }
        if current?.isTerminal == true, Self.textOnlyActions.contains(action) { return false }
        switch action {
        case #selector(toggleWordWrap(_:)): item.state = Prefs.wordWrap ? .on : .off
        case #selector(toggleLineNumbers(_:)): item.state = Prefs.showLineNumbers ? .on : .off
        case #selector(toggleCurrentLine(_:)): item.state = Prefs.highlightCurrentLine ? .on : .off
        case #selector(toggleInvisibles(_:)): item.state = Prefs.showInvisibles ? .on : .off
        case #selector(toggleUseSpaces(_:)): item.state = Prefs.useSpaces ? .on : .off
        case #selector(toggleAutoIndent(_:)): item.state = Prefs.autoIndent ? .on : .off
        case #selector(setTabWidth(_:)): item.state = item.tag == Prefs.tabWidth ? .on : .off
        case #selector(setLanguageFromMenu(_:)):
            item.state = (item.representedObject as? String) == current?.editor.language.id ? .on : .off
        case #selector(convertEncodingFromMenu(_:)):
            item.state = (item.representedObject as? String) == current?.encoding.rawValue ? .on : .off
        case #selector(setLineEndingFromMenu(_:)):
            item.state = (item.representedObject as? String) == current?.lineEnding.rawValue ? .on : .off
        case #selector(reopenWithEncoding(_:)), #selector(reloadFromDisk(_:)),
             #selector(revealInFinder(_:)), #selector(copyFilePath(_:)):
            return current?.url != nil
        case #selector(reopenClosedTab(_:)):
            return !closedFiles.isEmpty
        case #selector(toggleMarkdownPreview(_:)):
            item.state = current?.editor.isPreviewVisible == true ? .on : .off
        case #selector(setMarkdownViewMode(_:)):
            let modes: [Int: EditorView.ViewMode] = [1: .source, 2: .split, 3: .rendered]
            item.state = modes[item.tag] == current?.editor.viewMode ? .on : .off
        case #selector(setAppearance(_:)):
            item.state = (item.representedObject as? String) == Prefs.appearance ? .on : .off
        case #selector(setMarkdownOpenMode(_:)):
            item.state = (item.representedObject as? String) == Prefs.markdownOpenMode ? .on : .off
        case #selector(undoAction(_:)) where current?.editor.renderedHasFocus == true:
            item.title = "Undo"
            return true
        case #selector(redoAction(_:)) where current?.editor.renderedHasFocus == true:
            item.title = "Redo"
            return true
        case #selector(undoAction(_:)):
            item.title = activeUndoManager?.undoMenuItemTitle ?? "Undo"
            return activeUndoManager?.canUndo ?? false
        case #selector(redoAction(_:)):
            item.title = activeUndoManager?.redoMenuItemTitle ?? "Redo"
            return activeUndoManager?.canRedo ?? false
        case #selector(nextTab(_:)), #selector(previousTab(_:)):
            return docs.count > 1
        case #selector(selectTabNumber(_:)):
            return item.tag == 9 ? !docs.isEmpty : item.tag <= docs.count
        default:
            break
        }
        return true
    }

    /// Menu commands that only make sense for text tabs (disabled while a terminal tab is selected).
    private static let textOnlyActions: Set<Selector> = [
        #selector(saveDocument(_:)), #selector(saveDocumentAs(_:)),
        #selector(duplicateLine(_:)), #selector(deleteLine(_:)), #selector(moveLineUp(_:)), #selector(moveLineDown(_:)),
        #selector(toggleComment(_:)), #selector(indentLines(_:)), #selector(outdentLines(_:)),
        #selector(selectAllOccurrences(_:)), #selector(addNextOccurrence(_:)),
        #selector(addCaretAbove(_:)), #selector(addCaretBelow(_:)),
        #selector(insertDateTime(_:)), #selector(goToLine(_:)), #selector(textTool(_:)),
        #selector(showFind(_:)), #selector(showReplace(_:)), #selector(findNextAction(_:)),
        #selector(findPreviousAction(_:)), #selector(markAllAction(_:)), #selector(clearMarks(_:)),
        #selector(useSelectionForFind(_:)), #selector(setLanguageFromMenu(_:)),
        #selector(convertEncodingFromMenu(_:)), #selector(reopenWithEncoding(_:)), #selector(setLineEndingFromMenu(_:)),
        #selector(toggleMarkdownPreview(_:)), #selector(setMarkdownViewMode(_:)),
        #selector(markdownBold(_:)), #selector(markdownItalic(_:)), #selector(markdownStrikethrough(_:)),
        #selector(markdownLink(_:)), #selector(markdownCode(_:)), #selector(markdownHeading(_:)),
        #selector(exportHTML(_:)), #selector(copyAsHTML(_:)),
    ]

    // MARK: - Open Recent menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let paths = RecentFiles.paths
        for path in paths {
            let item = NSMenuItem(title: (path as NSString).abbreviatingWithTildeInPath,
                                  action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = path
            menu.addItem(item)
        }
        if !paths.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecent(_:)), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !paths.isEmpty
        menu.addItem(clear)
    }
}
