import AppKit
import Darwin
import SwiftTerm

/// A shell running in a terminal tab (SwiftTerm emulator + the user's login shell).
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    let view: LocalProcessTerminalView
    private(set) var directory: String
    private(set) var title = ""
    var onTitleChange: (() -> Void)?
    var onExit: (() -> Void)?

    init(directory: URL?) {
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        self.directory = (directory ?? FileManager.default.homeDirectoryForCurrentUser).path
        super.init()
        view.processDelegate = self
        view.optionAsMetaKey = false // keep ⌥ for typing special characters, like Terminal's default
        applyPreferences()
        start()
    }

    var folderName: String { (directory as NSString).lastPathComponent }

    func applyPreferences() {
        view.font = Prefs.editorFont
        // Resolve the system colors for the current light/dark appearance
        var fg = NSColor.textColor, bg = NSColor.textBackgroundColor
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            fg = NSColor.textColor.usingColorSpace(.sRGB) ?? fg
            bg = NSColor.textBackgroundColor.usingColorSpace(.sRGB) ?? bg
        }
        view.nativeForegroundColor = fg
        view.nativeBackgroundColor = bg
    }

    private func start() {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("TERM_PROGRAM=MacPad")
        if let path = ProcessInfo.processInfo.environment["PATH"] { env.append("PATH=\(path)") }
        if let tmp = ProcessInfo.processInfo.environment["TMPDIR"] { env.append("TMPDIR=\(tmp)") }
        view.startProcess(executable: shell, args: ["-l"], environment: env, currentDirectory: directory)
    }

    /// True if the shell is running a command right now (e.g. a build or ssh).
    var hasRunningCommand: Bool {
        guard let pid = view.process?.shellPid, pid > 0 else { return false }
        var children = [pid_t](repeating: 0, count: 64)
        let n = proc_listchildpids(pid, &children, Int32(children.count * MemoryLayout<pid_t>.size))
        return n > 0
    }

    func terminate() {
        guard view.process?.running == true else { return }
        view.terminate()
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async {
            self.title = title
            self.onTitleChange?()
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        let path = URL(string: directory)?.path ?? directory // OSC 7 sends file:// URLs
        DispatchQueue.main.async {
            self.directory = path
            self.onTitleChange?()
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { self.onExit?() }
    }
}
