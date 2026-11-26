# MacPad — handoff notes for Claude Code

MacPad is a native macOS (AppKit, Swift Package, no Xcode project) Notepad++-style text editor for macOS 13+.
**Renamed: the app is shown to users as "roxy++"** (bundle name, menus, window title, installers). Internal names stay MacPad
(Swift target, executable, bundle id `local.macpad.editor`, ~/Library/Application Support/MacPad) so settings and sessions carry over.

It was written in a Claude (Cowork) cloud session **without access to a Swift compiler**, so it has
**never been compiled yet**. Expect a few compile errors on the first build — fixing them is the first job.

## Goal of this session
1. Build the app: `bash build.sh` — fix any Swift compile errors / warnings that matter.
2. Launch and smoke-test: `open "roxy++.app"` (tabs, session restore, find/replace, find in files,
   text tools, Markdown Formatted / Split / Source views).
3. Build installers: `bash make-installer.sh` → `dist/roxy++-<version>.dmg` and `.pkg`.
4. Install: `bash build.sh install` (or the .pkg).

## Build facts
- `swift build -c release` (tools-version 5.9, Swift 5 language mode). Concurrency diagnostics are warnings, not errors.
- `build.sh` assembles `roxy++.app` (Info.plist, icon from Resources/AppIcon.png via sips/iconutil, ad-hoc codesign).
  It clears `.build` automatically if the folder was moved/renamed (SwiftPM caches absolute paths).
- `make-installer.sh` options: `VERSION`, `UNIVERSAL=1` (needs full Xcode), `DEVELOPER_ID`, `INSTALLER_ID`, `NOTARY_PROFILE`.
- Run scripts with `bash script.sh` (the user hit "Operation not permitted" running `./build.sh` from ~/Downloads;
  project now lives in ~/Projects/MacPad).

## Architecture (Sources/MacPad)
- `main.swift`, `AppDelegate.swift`, `MenuBuilder.swift` — app setup, programmatic menus (custom actions target the window controller).
- `MainWindowController.swift` — single window; tabs/documents, open/save/close, session, find bar actions,
  text tools, Markdown commands, encoding/line endings, menu validation, undo routing (`undoAction`/`redoAction`).
- `Document.swift` — one tab; owns its `EditorView`.
- `EditorView.swift` — TextKit 1 NSTextView + line-number ruler; syntax highlighting via layout-manager temporary attributes;
  Markdown view modes `.source / .split / .rendered` (rendered = editable WKWebView).
- `EditorTextView.swift` — editing behaviour: auto-indent, block indent, line ops, comments, multi-cursor
  (custom virtual carets, `applyEdits` coalesces edits into one undoable replace), Markdown list continuation.
- `LineNumberRuler.swift`, `TabBarView.swift` (custom-drawn), `StatusBarView.swift`, `FindBarView.swift`, `FindInFilesController.swift`.
- `Language.swift` (regex language definitions: `primary` = comments/strings alternation, `secondary` = keywords etc.), `Highlighter.swift` (+ Theme colors).
- `Markdown.swift` — Markdown→HTML renderer (Swift) + page/CSS + JS: `baseScript` and `editorScript`
  (contenteditable WYSIWYG, toolbar, HTML→Markdown converter `toMarkdown()`, messages to Swift via `window.webkit.messageHandlers.macpad`).
- `MarkdownPreviewView.swift` — WKWebView wrapper; content swapped via `macpadSetContent`, edits come back as `{type:'markdown'}` messages.
- `Search.swift` (SearchEngine, LineIndex, GlobFilter, FileSearcher), `TextTools.swift`, `FileIO.swift` (encodings/line endings),
  `Session.swift` (session.json + backups in ~/Library/Application Support/MacPad), `Prefs.swift` (UserDefaults).

## Known risk areas to check after it compiles
- `NSRulerView` subclass `required init(coder:)` signature; NSTextView overrides (`setSelectedRanges`, `insertText`, drag methods).
- Undo per tab via `undoManager(for:)` delegate + controller-routed Undo/Redo menu items.
- WKWebView message handler / `find(_:configuration:)` availability; rendered-mode flush before save (`flushRenderedEdits`).
- Large-file performance (highlighting limited to visible range above 1.5M chars).

## User preferences
- Concise explanations; non-technical wording for end-user instructions.
