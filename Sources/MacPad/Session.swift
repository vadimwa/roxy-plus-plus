import Foundation

struct SessionTab: Codable {
    var id: UUID
    var path: String?
    var untitledIndex: Int
    var dirty: Bool
    var hasBackup: Bool
    var encoding: FileEncoding
    var lineEnding: LineEnding
    var language: String
    var selection: Int
    var modificationDate: Date?
}

struct SessionData: Codable {
    var tabs: [SessionTab]
    var selected: Int
}

/// Notepad++-style session: remembers open tabs and keeps unsaved text in backup files,
/// so quitting never asks to save and everything comes back on launch.
@MainActor
final class SessionStore {
    private let fm = FileManager.default
    let directory: URL
    let backupDirectory: URL
    private var sessionURL: URL { directory.appendingPathComponent("session.json") }
    private var lastWritten: Data?

    init() {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        directory = base.appendingPathComponent("MacPad", isDirectory: true)
        backupDirectory = directory.appendingPathComponent("backup", isDirectory: true)
        try? fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
    }

    private func backupURL(_ id: UUID) -> URL {
        backupDirectory.appendingPathComponent(id.uuidString + ".txt")
    }

    func backup(for id: UUID) -> String? {
        try? String(contentsOf: backupURL(id), encoding: .utf8)
    }

    func save(docs: [Document], selectedIndex: Int) {
        try? fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        var tabs: [SessionTab] = []
        var keep = Set<String>()

        for doc in docs {
            let needsBackup = doc.isDirty || (doc.url == nil && !doc.text.isEmpty)
            if needsBackup {
                let file = backupURL(doc.id)
                keep.insert(file.lastPathComponent)
                if doc.backedUpChangeCount != doc.changeCount || !fm.fileExists(atPath: file.path) {
                    do {
                        try Data(doc.text.utf8).write(to: file, options: .atomic)
                        doc.backedUpChangeCount = doc.changeCount
                    } catch {
                        NSLog("%@", "MacPad: backup failed: \(error.localizedDescription)")
                    }
                }
            }
            tabs.append(SessionTab(
                id: doc.id,
                path: doc.url?.path,
                untitledIndex: doc.untitledIndex,
                dirty: doc.isDirty,
                hasBackup: needsBackup,
                encoding: doc.encoding,
                lineEnding: doc.lineEnding,
                language: doc.editor.language.id,
                selection: doc.editor.textView.selectedRange().location,
                modificationDate: doc.fileModificationDate))
        }

        if let files = try? fm.contentsOfDirectory(atPath: backupDirectory.path) {
            for f in files where !keep.contains(f) {
                try? fm.removeItem(at: backupDirectory.appendingPathComponent(f))
            }
        }

        let session = SessionData(tabs: tabs, selected: selectedIndex)
        if let data = try? JSONEncoder().encode(session), data != lastWritten {
            try? data.write(to: sessionURL, options: .atomic)
            lastWritten = data
        }
    }

    func load() -> SessionData? {
        guard let data = try? Data(contentsOf: sessionURL) else { return nil }
        return try? JSONDecoder().decode(SessionData.self, from: data)
    }
}

enum RecentFiles {
    private static let key = "recentFiles"

    static var paths: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func add(_ url: URL) {
        var list = paths
        list.removeAll { $0 == url.path }
        list.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(20)), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
