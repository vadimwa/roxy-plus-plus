import AppKit

enum MenuBuilder {
    static func build(controller c: MainWindowController) -> NSMenu {
        let main = NSMenu()

        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            item.submenu = menu
            main.addItem(item)
            return menu
        }

        /// Item targeting the window controller.
        @discardableResult
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
                 _ mods: NSEvent.ModifierFlags = [.command], tag: Int = 0, rep: Any? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = c
            item.tag = tag
            item.representedObject = rep
            menu.addItem(item)
            return item
        }

        /// Item sent through the responder chain (standard text / app actions).
        @discardableResult
        func std(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
                 _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            menu.addItem(item)
            return item
        }

        func sub(_ parent: NSMenu, _ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            item.submenu = menu
            parent.addItem(item)
            return menu
        }

        func key(_ functionKey: Int) -> String {
            String(Character(Unicode.Scalar(UInt32(functionKey))!))
        }
        let up = key(NSUpArrowFunctionKey)
        let down = key(NSDownArrowFunctionKey)

        // App
        let app = submenu("roxy++")
        std(app, "About roxy++", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        let services = sub(app, "Services")
        NSApp.servicesMenu = services
        app.addItem(.separator())
        std(app, "Hide roxy++", #selector(NSApplication.hide(_:)), "h")
        std(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        std(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        std(app, "Quit roxy++", #selector(NSApplication.terminate(_:)), "q")

        // File
        let file = submenu("File")
        add(file, "New", #selector(MainWindowController.newDocument(_:)), "n")
        add(file, "New Terminal Tab", #selector(MainWindowController.newTerminalTab(_:)), "`", [.control])
        add(file, "Open…", #selector(MainWindowController.openDocument(_:)), "o")
        let recent = sub(file, "Open Recent")
        recent.delegate = c
        add(file, "Reopen Closed Tab", #selector(MainWindowController.reopenClosedTab(_:)), "t", [.command, .shift])
        file.addItem(.separator())
        add(file, "Save", #selector(MainWindowController.saveDocument(_:)), "s")
        add(file, "Save As…", #selector(MainWindowController.saveDocumentAs(_:)), "s", [.command, .shift])
        add(file, "Save All", #selector(MainWindowController.saveAllDocuments(_:)), "s", [.command, .option])
        add(file, "Reload from Disk", #selector(MainWindowController.reloadFromDisk(_:)))
        file.addItem(.separator())
        add(file, "Close Tab", #selector(MainWindowController.closeTab(_:)), "w")
        add(file, "Close All Tabs", #selector(MainWindowController.closeAllTabs(_:)), "w", [.command, .shift])
        add(file, "Close Other Tabs", #selector(MainWindowController.closeOtherTabs(_:)))
        file.addItem(.separator())
        add(file, "Reveal in Finder", #selector(MainWindowController.revealInFinder(_:)), "r", [.command, .shift])
        add(file, "Open in Terminal", #selector(MainWindowController.openInTerminal(_:)), "t", [.command, .control])
        add(file, "Copy Full Path", #selector(MainWindowController.copyFilePath(_:)), "c", [.command, .option, .shift])

        // Edit
        let edit = submenu("Edit")
        add(edit, "Undo", #selector(MainWindowController.undoAction(_:)), "z")
        add(edit, "Redo", #selector(MainWindowController.redoAction(_:)), "z", [.command, .shift])
        edit.addItem(.separator())
        std(edit, "Cut", #selector(NSText.cut(_:)), "x")
        std(edit, "Copy", #selector(NSText.copy(_:)), "c")
        std(edit, "Paste", #selector(NSText.paste(_:)), "v")
        std(edit, "Delete", #selector(NSText.delete(_:)))
        std(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        let lines = sub(edit, "Line")
        add(lines, "Duplicate Line", #selector(MainWindowController.duplicateLine(_:)), "d")
        add(lines, "Delete Line", #selector(MainWindowController.deleteLine(_:)), "k", [.command, .shift])
        add(lines, "Move Line Up", #selector(MainWindowController.moveLineUp(_:)), up, [.command, .control])
        add(lines, "Move Line Down", #selector(MainWindowController.moveLineDown(_:)), down, [.command, .control])
        add(lines, "Indent", #selector(MainWindowController.indentLines(_:)), "]")
        add(lines, "Outdent", #selector(MainWindowController.outdentLines(_:)), "[")
        add(edit, "Toggle Comment", #selector(MainWindowController.toggleComment(_:)), "/")
        edit.addItem(.separator())
        let cursors = sub(edit, "Multiple Cursors")
        add(cursors, "Add Cursor Above", #selector(MainWindowController.addCaretAbove(_:)), up, [.control, .shift])
        add(cursors, "Add Cursor Below", #selector(MainWindowController.addCaretBelow(_:)), down, [.control, .shift])
        add(cursors, "Add Next Occurrence", #selector(MainWindowController.addNextOccurrence(_:)), "e", [.command, .option])
        add(cursors, "Select All Occurrences", #selector(MainWindowController.selectAllOccurrences(_:)), "g", [.command, .control])
        cursors.addItem(.separator())
        let hint = NSMenuItem(title: "Tip: ⌥-drag for column selection, ⌘-drag to add selections, Esc to collapse",
                              action: nil, keyEquivalent: "")
        hint.isEnabled = false
        cursors.addItem(hint)
        edit.addItem(.separator())
        add(edit, "Go to Line…", #selector(MainWindowController.goToLine(_:)), "l")
        add(edit, "Insert Date & Time", #selector(MainWindowController.insertDateTime(_:)))

        // Find
        let find = submenu("Search")
        add(find, "Find…", #selector(MainWindowController.showFind(_:)), "f")
        add(find, "Replace…", #selector(MainWindowController.showReplace(_:)), "f", [.command, .option])
        add(find, "Find Next", #selector(MainWindowController.findNextAction(_:)), "g")
        add(find, "Find Previous", #selector(MainWindowController.findPreviousAction(_:)), "g", [.command, .shift])
        add(find, "Use Selection for Find", #selector(MainWindowController.useSelectionForFind(_:)), "e")
        find.addItem(.separator())
        add(find, "Find in Files…", #selector(MainWindowController.showFindInFiles(_:)), "f", [.command, .shift])
        find.addItem(.separator())
        add(find, "Mark All", #selector(MainWindowController.markAllAction(_:)), "m", [.command, .shift])
        add(find, "Clear Marks", #selector(MainWindowController.clearMarks(_:)))

        // Text tools
        let text = submenu("Text")
        let tool = #selector(MainWindowController.textTool(_:))
        let caseMenu = sub(text, "Case")
        add(caseMenu, "UPPERCASE", tool, "u", [.command, .shift], tag: TextTool.upper.rawValue)
        add(caseMenu, "lowercase", tool, "u", [.command], tag: TextTool.lower.rawValue)
        add(caseMenu, "Title Case", tool, tag: TextTool.title.rawValue)
        add(caseMenu, "iNVERT cASE", tool, tag: TextTool.invertCase.rawValue)
        let sortMenu = sub(text, "Sort & Order Lines")
        add(sortMenu, "Sort Ascending", tool, tag: TextTool.sortAsc.rawValue)
        add(sortMenu, "Sort Descending", tool, tag: TextTool.sortDesc.rawValue)
        add(sortMenu, "Sort Case-Insensitive", tool, tag: TextTool.sortCaseInsensitive.rawValue)
        add(sortMenu, "Sort Numerically (Natural)", tool, tag: TextTool.sortNumeric.rawValue)
        sortMenu.addItem(.separator())
        add(sortMenu, "Reverse Lines", tool, tag: TextTool.reverseLines.rawValue)
        add(sortMenu, "Shuffle Lines", tool, tag: TextTool.shuffleLines.rawValue)
        let lineOps = sub(text, "Line Operations")
        add(lineOps, "Remove Duplicate Lines", tool, tag: TextTool.uniqueLines.rawValue)
        add(lineOps, "Remove Empty Lines", tool, tag: TextTool.removeEmptyLines.rawValue)
        add(lineOps, "Join Lines", tool, "j", [.control], tag: TextTool.joinLines.rawValue)
        let blanks = sub(text, "Whitespace")
        add(blanks, "Trim Trailing Space", tool, tag: TextTool.trimTrailing.rawValue)
        add(blanks, "Trim Leading Space", tool, tag: TextTool.trimLeading.rawValue)
        add(blanks, "Trim Leading and Trailing Space", tool, tag: TextTool.trimBoth.rawValue)
        blanks.addItem(.separator())
        add(blanks, "Tabs to Spaces", tool, tag: TextTool.tabsToSpaces.rawValue)
        add(blanks, "Leading Spaces to Tabs", tool, tag: TextTool.spacesToTabs.rawValue)
        text.addItem(.separator())
        add(text, "Format JSON", tool, "j", [.command, .option, .shift], tag: TextTool.jsonPretty.rawValue)
        add(text, "Minify JSON", tool, tag: TextTool.jsonMinify.rawValue)
        text.addItem(.separator())
        let codec = sub(text, "Encode / Decode")
        add(codec, "Base64 Encode", tool, tag: TextTool.base64Encode.rawValue)
        add(codec, "Base64 Decode", tool, tag: TextTool.base64Decode.rawValue)
        add(codec, "URL Encode", tool, tag: TextTool.urlEncode.rawValue)
        add(codec, "URL Decode", tool, tag: TextTool.urlDecode.rawValue)
        add(codec, "HTML Escape", tool, tag: TextTool.htmlEscape.rawValue)
        add(codec, "HTML Unescape", tool, tag: TextTool.htmlUnescape.rawValue)
        let note = NSMenuItem(title: "Tools apply to the selection, or the whole document if nothing is selected",
                              action: nil, keyEquivalent: "")
        note.isEnabled = false
        text.addItem(.separator())
        text.addItem(note)

        // Markdown
        let md = submenu("Markdown")
        let mode = #selector(MainWindowController.setMarkdownViewMode(_:))
        add(md, "Formatted (Editable)", mode, "1", [.command, .option], tag: 3)
        add(md, "Split: Source + Preview", mode, "2", [.command, .option], tag: 2)
        add(md, "Source Only", mode, "3", [.command, .option], tag: 1)
        add(md, "Toggle Preview", #selector(MainWindowController.toggleMarkdownPreview(_:)), "p", [.command, .option])
        let openIn = sub(md, "Open Markdown Files As")
        let openMode = #selector(MainWindowController.setMarkdownOpenMode(_:))
        add(openIn, "Formatted (Editable)", openMode, rep: "rendered")
        add(openIn, "Split: Source + Preview", openMode, rep: "split")
        add(openIn, "Source Only", openMode, rep: "source")
        md.addItem(.separator())
        let heading = #selector(MainWindowController.markdownHeading(_:))
        add(md, "Heading 1", heading, "1", [.command, .control], tag: 1)
        add(md, "Heading 2", heading, "2", [.command, .control], tag: 2)
        add(md, "Heading 3", heading, "3", [.command, .control], tag: 3)
        add(md, "Normal Text", heading, "0", [.command, .control], tag: 0)
        md.addItem(.separator())
        add(md, "Bold", #selector(MainWindowController.markdownBold(_:)), "b")
        add(md, "Italic", #selector(MainWindowController.markdownItalic(_:)), "i")
        add(md, "Strikethrough", #selector(MainWindowController.markdownStrikethrough(_:)), "x", [.command, .shift])
        add(md, "Code", #selector(MainWindowController.markdownCode(_:)), "k", [.command, .option])
        add(md, "Link", #selector(MainWindowController.markdownLink(_:)), "k")
        md.addItem(.separator())
        add(md, "Export as HTML…", #selector(MainWindowController.exportHTML(_:)), "e", [.command, .shift])
        add(md, "Copy as HTML", #selector(MainWindowController.copyAsHTML(_:)), "c", [.command, .shift])

        // View
        let view = submenu("View")
        let appearance = sub(view, "Appearance")
        add(appearance, "Same as System", #selector(MainWindowController.setAppearance(_:)), rep: "system")
        add(appearance, "Light", #selector(MainWindowController.setAppearance(_:)), rep: "light")
        add(appearance, "Dark", #selector(MainWindowController.setAppearance(_:)), rep: "dark")
        view.addItem(.separator())
        add(view, "Word Wrap", #selector(MainWindowController.toggleWordWrap(_:)), "w", [.command, .option])
        add(view, "Line Numbers", #selector(MainWindowController.toggleLineNumbers(_:)))
        add(view, "Highlight Current Line", #selector(MainWindowController.toggleCurrentLine(_:)))
        add(view, "Show Invisible Characters", #selector(MainWindowController.toggleInvisibles(_:)))
        view.addItem(.separator())
        add(view, "Zoom In", #selector(MainWindowController.zoomIn(_:)), "=")
        add(view, "Zoom Out", #selector(MainWindowController.zoomOut(_:)), "-")
        add(view, "Actual Size", #selector(MainWindowController.zoomReset(_:)), "0")
        view.addItem(.separator())
        let language = sub(view, "Language")
        for l in Language.all {
            add(language, l.name, #selector(MainWindowController.setLanguageFromMenu(_:)), rep: l.id)
        }
        let indentation = sub(view, "Indentation")
        add(indentation, "Indent Using Spaces", #selector(MainWindowController.toggleUseSpaces(_:)))
        add(indentation, "Auto-Indent", #selector(MainWindowController.toggleAutoIndent(_:)))
        indentation.addItem(.separator())
        for w in [2, 3, 4, 8] {
            add(indentation, "Tab Width: \(w)", #selector(MainWindowController.setTabWidth(_:)), tag: w)
        }
        view.addItem(.separator())
        std(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])

        // Encoding
        let encoding = submenu("Encoding")
        let convert = sub(encoding, "Save With Encoding")
        for e in FileEncoding.allCases {
            add(convert, e.label, #selector(MainWindowController.convertEncodingFromMenu(_:)), rep: e.rawValue)
        }
        let reopen = sub(encoding, "Reopen With Encoding")
        for e in FileEncoding.allCases {
            add(reopen, e.label, #selector(MainWindowController.reopenWithEncoding(_:)), rep: e.rawValue)
        }
        encoding.addItem(.separator())
        for eol in LineEnding.allCases {
            add(encoding, "Line Endings: " + eol.label, #selector(MainWindowController.setLineEndingFromMenu(_:)), rep: eol.rawValue)
        }

        // Window
        let window = submenu("Window")
        std(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        std(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        add(window, "Next Tab", #selector(MainWindowController.nextTab(_:)), "}", [.command])
        add(window, "Previous Tab", #selector(MainWindowController.previousTab(_:)), "{", [.command])
        // Ctrl-Tab / Ctrl-Shift-Tab (hidden duplicates that only provide the shortcut)
        add(window, "Next Tab (Ctrl-Tab)", #selector(MainWindowController.nextTab(_:)), "\t", [.control]).isHidden = true
        add(window, "Previous Tab (Ctrl-Shift-Tab)", #selector(MainWindowController.previousTab(_:)), "\t", [.control, .shift]).isHidden = true
        window.addItem(.separator())
        for n in 1...9 {
            add(window, n == 9 ? "Last Tab" : "Tab \(n)", #selector(MainWindowController.selectTabNumber(_:)), "\(n)", tag: n)
        }
        NSApp.windowsMenu = window

        return main
    }
}
