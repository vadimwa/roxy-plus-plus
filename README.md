# MacPad

A fast, native (AppKit) Notepad++-style text editor for macOS 13+.

## Build & install

You only need Apple's Command Line Tools (no full Xcode):

```bash
xcode-select --install          # once, if you don't have them
cd MacPad
chmod +x build.sh
./build.sh install              # builds MacPad.app and copies it to /Applications
```

`./build.sh` alone builds `MacPad.app` in the project folder. Because you build it yourself, Gatekeeper won't block it.

Optional terminal shortcut (add to `~/.zshrc`):

```bash
macpad() { open -a MacPad "$@"; }
```

To make it the default for a file type: Finder ▸ select a file ▸ Get Info ▸ Open with: MacPad ▸ Change All…

## Installers (.dmg / .pkg)

```bash
bash make-installer.sh                 # creates dist/MacPad-1.0.dmg and dist/MacPad-1.0.pkg
VERSION=1.1 bash make-installer.sh     # set the version number
UNIVERSAL=1 bash make-installer.sh     # Apple Silicon + Intel (requires the full Xcode app)
```

- **.dmg**: open it and drag MacPad onto Applications.
- **.pkg**: double-click and follow the installer; it puts MacPad in /Applications.
- Without an Apple Developer ID the installers are unsigned. That's fine on your own Macs; on other Macs open MacPad the first time with right-click ▸ Open (or `xattr -cr /Applications/MacPad.app`).
- For warning-free distribution (Apple Developer Program): set `DEVELOPER_ID`, `INSTALLER_ID` and `NOTARY_PROFILE` (see the top of make-installer.sh) to sign and notarize.

## Features

**Tabs & sessions (like Notepad++)**
- Tabs with unsaved-dot indicator; drag to reorder, middle-click or × to close, double-click empty bar for a new tab, right-click for Close Others / Close to the Right / Copy Path / Reveal in Finder
- Quit any time: open tabs, unsaved edits and untitled scratch tabs are restored on next launch (backups every 5 s in `~/Library/Application Support/MacPad`)
- Reopen closed tab (⇧⌘T), Open Recent, drag files onto the window, detects files changed on disk

**Editing**
- Syntax highlighting: C/C++/Obj-C, C#, CSS/SCSS, Dockerfile, Go, HTML/XML, INI/TOML/.env, Java/Kotlin, JavaScript/TypeScript, JSON, Log files, Makefile, Markdown, PHP, Python, Ruby, Rust, Shell, SQL, Swift, YAML — follows light/dark mode
- Line numbers (click to select a line), current-line highlight, word wrap, show invisibles, zoom
- Auto-indent, Tab / ⇧Tab block indent, spaces-or-tabs and tab width settings
- Line ops: duplicate ⌘D, delete ⇧⌘K, move ⌃⌘↑/↓, toggle comment ⌘/, go to line ⌘L
- Multi-cursor: ⌃⇧↑/↓ add cursor, ⌥⌘E add next occurrence, ⌃⌘G select all occurrences, ⌥-drag column selection, ⌘-drag extra selections, Esc to collapse. Pasting N lines into N cursors puts one line per cursor.

**Search**
- Find / Replace bar (⌘F / ⌥⌘F): match case, whole word, regex (ICU; `$1` groups and `\n` `\t` in replacements), wrap, count, Mark All
- Find in Files (⇧⌘F): folder + filters like `*.swift *.md !node_modules`, results list (double-click to jump), Replace in Files

**Markdown (.md)**
- Opens as a **formatted, editable document** (no markup visible) — edit it like a word processor; MacPad saves it back as Markdown. Switch views in the status bar or Markdown menu: Formatted ⌥⌘1, Split (source + live preview) ⌥⌘2, Source ⌥⌘3. Choose the default under Markdown ▸ Open Markdown Files As.
- Formatted view: toolbar for headings, bold/italic/strike, code, links, bullet/numbered/task lists, quotes, code blocks, tables, rules; clickable task checkboxes; Tab / ⇧Tab nests list items; typing `# `, `## `, `- `, `1. `, `> `, `[] ` at the start of a line converts it; ⌘-click opens links; ⌘F searches the formatted text
- Shortcuts (all views): Bold ⌘B, Italic ⌘I, Strikethrough ⇧⌘X, Code ⌥⌘K, Link ⌘K, Heading 1–3 ⌃⌘1–3, Normal text ⌃⌘0
- Source view: Enter continues lists and quotes; split preview scrolls with the editor; YAML front matter is preserved
- Export as HTML (⇧⌘E) or Copy as HTML (⇧⌘C)
- Note: editing in the formatted view normalises Markdown style (e.g. `*` lists become `-`, paragraphs keep their line breaks). Files you only read are never changed.

**Text menu** (applies to the selection, or the whole document)
- UPPER / lower / Title / iNVERT case
- Sort (asc, desc, case-insensitive, natural/numeric), reverse, shuffle, remove duplicates / empty lines, join lines
- Trim whitespace, tabs ↔ spaces
- Format / minify JSON (keeps key order)
- Base64, URL, HTML encode/decode

**Encoding & line endings**
- Auto-detects UTF-8, UTF-8 BOM, UTF-16 LE/BE, Windows-1252, Latin-1
- Status bar pickers to change language, line endings (LF / CRLF / CR) and save encoding; Encoding ▸ Reopen With Encoding

## Project layout

```
Package.swift                Swift package (single executable target)
build.sh                     builds and bundles MacPad.app
Resources/AppIcon.png        icon (converted to .icns by build.sh)
Sources/MacPad/
  main.swift, AppDelegate.swift, MenuBuilder.swift
  MainWindowController.swift  tabs, documents, find, session, menu actions
  EditorView.swift            scroll view + text view + gutter for one tab
  EditorTextView.swift        editing behaviour, multi-cursor, line operations
  LineNumberRuler.swift       line-number gutter
  TabBarView.swift, StatusBarView.swift, FindBarView.swift, FindInFilesController.swift
  Language.swift, Highlighter.swift   regex-based highlighting + theme colors
  Search.swift, TextTools.swift, FileIO.swift, Session.swift, Prefs.swift, Document.swift
```

Adding a language: append a `.make(...)` entry in `Language.swift` with its extensions, comment/string patterns (`primary`) and keyword/number patterns (`secondary`).

## Troubleshooting

- `swift: command not found` → run `xcode-select --install`.
- Build errors after a macOS/Xcode update → `rm -rf .build` and build again.
- Reset the session (start with no tabs) → quit MacPad and delete `~/Library/Application Support/MacPad`.
