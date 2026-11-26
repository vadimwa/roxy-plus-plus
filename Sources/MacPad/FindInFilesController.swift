import AppKit

/// "Find in Files" window: search a folder (with filters), list hits, double-click to open, replace across files.
final class FindInFilesController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let findField = NSTextField()
    let replaceField = NSTextField()
    let directoryField = NSTextField()
    let filterField = NSTextField()
    let caseBox = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
    let wordBox = NSButton(checkboxWithTitle: "Whole word", target: nil, action: nil)
    let regexBox = NSButton(checkboxWithTitle: "Regular expression", target: nil, action: nil)
    let subfoldersBox = NSButton(checkboxWithTitle: "Include subfolders", target: nil, action: nil)
    let hiddenBox = NSButton(checkboxWithTitle: "Include hidden files", target: nil, action: nil)
    let statusLabel = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private var findButton: NSButton!
    private var replaceButton: NSButton!
    private var stopButton: NSButton!

    private(set) var hits: [SearchHit] = []
    private var rootPath = ""
    private var searchToken = UUID()
    private var cancelFlag = CancelFlag()

    var onOpenHit: ((SearchHit) -> Void)?
    /// Called with the files to change; returns a summary message.
    var onReplaceInFiles: (([URL], SearchOptions, String) -> String)?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 580),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Find in Files"
        window.minSize = NSSize(width: 640, height: 380)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MacPadFindInFiles")
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }


    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        findButton = NSButton(title: "Find All", target: self, action: #selector(findAll(_:)))
        findButton.keyEquivalent = "\r"
        replaceButton = NSButton(title: "Replace in Files", target: self, action: #selector(replaceInFiles(_:)))
        stopButton = NSButton(title: "Stop", target: self, action: #selector(stop(_:)))
        stopButton.isEnabled = false
        let browseButton = NSButton(title: "Browse…", target: self, action: #selector(browse(_:)))

        filterField.stringValue = "*"
        filterField.placeholderString = "*.swift *.txt !node_modules !*.min.js"
        filterField.toolTip = "Space-separated file patterns. Prefix with ! to exclude files or folders."
        findField.placeholderString = "Text or regular expression"
        replaceField.placeholderString = "Replacement ($1 for groups when using regex)"
        directoryField.placeholderString = "Folder to search"
        subfoldersBox.state = .on
        for field in [findField, replaceField, directoryField, filterField] {
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.usesSingleLineMode = true
            field.cell?.isScrollable = true
            field.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        }

        func label(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.alignment = .right
            return l
        }

        let options = NSStackView(views: [caseBox, wordBox, regexBox, subfoldersBox, hiddenBox])
        options.orientation = .horizontal
        options.spacing = 12

        let grid = NSGridView(views: [
            [label("Find what:"), findField, findButton],
            [label("Replace with:"), replaceField, replaceButton],
            [label("Directory:"), directoryField, browseButton],
            [label("Filters:"), filterField, stopButton],
            [NSGridCell.emptyContentView, options, NSGridCell.emptyContentView],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 2).xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false
        for row in 0..<grid.numberOfRows { grid.row(at: row).yPlacement = .center }

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.lineBreakMode = .byTruncatingTail

        let columns: [(String, String, CGFloat)] = [("file", "File", 280), ("line", "Line", 56), ("text", "Text", 520)]
        for (id, title, width) in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            if let cell = col.dataCell as? NSTextFieldCell {
                cell.font = id == "text" ? .monospacedSystemFont(ofSize: 11, weight: .regular) : .systemFont(ofSize: 11)
                cell.lineBreakMode = id == "file" ? .byTruncatingHead : .byTruncatingTail
            }
            table.addTableColumn(col)
        }
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected(_:))
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(grid)
        content.addSubview(statusLabel)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            statusLabel.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        statusLabel.stringValue = "Double-click a result to open it."
    }

    func present(directory: URL?, query: String?) {
        if directoryField.stringValue.isEmpty || directory != nil {
            directoryField.stringValue = (directory ?? FileManager.default.homeDirectoryForCurrentUser).path
        }
        if let query, !query.isEmpty { findField.stringValue = query }
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeFirstResponder(findField)
    }

    // MARK: - Actions

    private func currentOptions() -> SearchOptions {
        SearchOptions(query: findField.stringValue,
                      caseSensitive: caseBox.state == .on,
                      wholeWord: wordBox.state == .on,
                      regex: regexBox.state == .on,
                      wrap: false)
    }

    private func rootURL() -> URL? {
        let path = (directoryField.stringValue as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            statusLabel.stringValue = "Choose an existing folder to search."
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func setBusy(_ busy: Bool) {
        findButton.isEnabled = !busy
        replaceButton.isEnabled = !busy
        stopButton.isEnabled = busy
    }

    @objc func browse(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if !directoryField.stringValue.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (directoryField.stringValue as NSString).expandingTildeInPath)
        }
        if let window {
            panel.beginSheetModal(for: window) { [weak self] response in
                if response == .OK, let url = panel.url { self?.directoryField.stringValue = url.path }
            }
        }
    }

    @objc func stop(_ sender: Any?) {
        cancelFlag.cancel()
    }

    @objc func findAll(_ sender: Any?) {
        let options = currentOptions()
        guard !options.query.isEmpty else { statusLabel.stringValue = "Enter something to find."; return }
        guard let root = rootURL() else { return }
        let regex: NSRegularExpression
        do { regex = try SearchEngine.regex(options) } catch {
            statusLabel.stringValue = "Invalid regular expression."
            return
        }
        rootPath = root.path
        hits = []
        table.reloadData()
        setBusy(true)
        let flag = CancelFlag()
        cancelFlag = flag
        statusLabel.stringValue = "Searching…"
        let token = UUID()
        searchToken = token
        let filter = GlobFilter(filterField.stringValue)
        let recursive = subfoldersBox.state == .on
        let hidden = hiddenBox.state == .on

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = FileSearcher.search(
                root: root, regex: regex, filter: filter, recursive: recursive, includeHidden: hidden,
                isCancelled: { flag.isCancelled },
                progress: { n in
                    DispatchQueue.main.async {
                        guard let self, self.searchToken == token else { return }
                        self.statusLabel.stringValue = "Searching… \(n) files scanned"
                    }
                })
            DispatchQueue.main.async {
                guard let self, self.searchToken == token else { return }
                self.hits = result.hits
                self.table.reloadData()
                self.setBusy(false)
                var msg = "\(result.hits.count) match\(result.hits.count == 1 ? "" : "es") in \(result.filesWithHits) file\(result.filesWithHits == 1 ? "" : "s") (\(result.filesScanned) scanned)"
                if result.truncated { msg += " — stopped at \(FileSearcher.maxHits) matches" }
                if flag.isCancelled { msg += " — stopped" }
                self.statusLabel.stringValue = msg
            }
        }
    }

    @objc func replaceInFiles(_ sender: Any?) {
        let options = currentOptions()
        guard !options.query.isEmpty else { statusLabel.stringValue = "Enter something to find."; return }
        if hits.isEmpty {
            statusLabel.stringValue = "Run Find All first, then Replace in Files changes the files listed."
            return
        }
        var seen = Set<String>()
        let urls = hits.compactMap { hit -> URL? in seen.insert(hit.url.path).inserted ? hit.url : nil }
        let alert = NSAlert()
        alert.messageText = "Replace in \(urls.count) file\(urls.count == 1 ? "" : "s")?"
        alert.informativeText = "Files that aren't open in roxy++ are changed and saved directly and can't be undone. Files open in tabs are changed in the editor (undoable) and left unsaved."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let summary = onReplaceInFiles?(urls, options, replaceField.stringValue) ?? ""
        findAll(nil)
        statusLabel.stringValue = summary
    }

    @objc func openSelected(_ sender: Any?) {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard hits.indices.contains(row) else { return }
        onOpenHit?(hits[row])
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { hits.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard hits.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let hit = hits[row]
        switch id {
        case "file":
            let path = hit.url.path
            if path.hasPrefix(rootPath + "/") { return String(path.dropFirst(rootPath.count + 1)) }
            return path
        case "line":
            return hit.line
        default:
            return hit.preview
        }
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool { false }
}

/// Thread-safe cancellation flag for background searches.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock(); value = true; lock.unlock()
    }
}
