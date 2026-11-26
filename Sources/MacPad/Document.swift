import AppKit

/// One open tab: its file info plus its own editor view (so undo, scroll and selection survive tab switches).
@MainActor
final class Document {
    let id: UUID
    var url: URL?
    var untitledIndex: Int
    var encoding: FileEncoding
    var lineEnding: LineEnding
    var isDirty = false
    var fileModificationDate: Date?
    var changeCount = 0
    var backedUpChangeCount = -1
    var pendingSelection: Int?
    let editor: EditorView
    /// Set for terminal tabs; the (empty, hidden) editor is then unused.
    let terminal: TerminalSession?

    init(id: UUID = UUID(), url: URL?, untitledIndex: Int, text: String,
         encoding: FileEncoding = .utf8, lineEnding: LineEnding = .lf, language: Language) {
        self.id = id
        self.url = url
        self.untitledIndex = untitledIndex
        self.encoding = encoding
        self.lineEnding = lineEnding
        self.editor = EditorView(text: text, language: language)
        self.terminal = nil
    }

    /// A terminal tab starting in `directory` (home folder if nil).
    init(terminalIn directory: URL?) {
        self.id = UUID()
        self.url = nil
        self.untitledIndex = 0
        self.encoding = .utf8
        self.lineEnding = .lf
        self.editor = EditorView(text: "", language: .plain)
        self.terminal = TerminalSession(directory: directory)
    }

    var isTerminal: Bool { terminal != nil }

    /// The view shown in the editor area for this tab.
    var contentView: NSView { terminal?.view ?? editor }

    var text: String { editor.textView.string }

    var displayName: String {
        if let terminal { return "Terminal — " + terminal.folderName }
        return url?.lastPathComponent ?? "new \(untitledIndex)"
    }

    func write(to url: URL) throws {
        let data = try FileIO.encode(text, encoding: encoding, lineEnding: lineEnding)
        try data.write(to: url, options: .atomic)
        self.url = url
        isDirty = false
        fileModificationDate = FileIO.modificationDate(url)
    }

    func isSameFile(_ other: URL) -> Bool {
        guard let url else { return false }
        return url.standardizedFileURL.resolvingSymlinksInPath().path == other.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
