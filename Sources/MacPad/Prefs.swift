import AppKit

/// User preferences, persisted in UserDefaults.
enum Prefs {
    private static var d: UserDefaults { UserDefaults.standard }

    static func register() {
        d.register(defaults: [
            "fontSize": 13.0,
            "wordWrap": false,
            "tabWidth": 4,
            "useSpaces": true,
            "autoIndent": true,
            "showLineNumbers": true,
            "highlightCurrentLine": true,
            "showInvisibles": false,
            "markdownOpenMode": "rendered",
        ])
    }

    static var fontSize: CGFloat {
        get { CGFloat(d.double(forKey: "fontSize")) }
        set { d.set(Double(min(48, max(8, newValue))), forKey: "fontSize") }
    }
    static var wordWrap: Bool {
        get { d.bool(forKey: "wordWrap") }
        set { d.set(newValue, forKey: "wordWrap") }
    }
    static var tabWidth: Int {
        get { max(1, d.integer(forKey: "tabWidth")) }
        set { d.set(newValue, forKey: "tabWidth") }
    }
    static var useSpaces: Bool {
        get { d.bool(forKey: "useSpaces") }
        set { d.set(newValue, forKey: "useSpaces") }
    }
    static var autoIndent: Bool {
        get { d.bool(forKey: "autoIndent") }
        set { d.set(newValue, forKey: "autoIndent") }
    }
    static var showLineNumbers: Bool {
        get { d.bool(forKey: "showLineNumbers") }
        set { d.set(newValue, forKey: "showLineNumbers") }
    }
    static var highlightCurrentLine: Bool {
        get { d.bool(forKey: "highlightCurrentLine") }
        set { d.set(newValue, forKey: "highlightCurrentLine") }
    }
    static var showInvisibles: Bool {
        get { d.bool(forKey: "showInvisibles") }
        set { d.set(newValue, forKey: "showInvisibles") }
    }

    /// How Markdown files open: "rendered" (editable formatted view), "split" or "source".
    static var markdownOpenMode: String {
        get { d.string(forKey: "markdownOpenMode") ?? "rendered" }
        set { d.set(newValue, forKey: "markdownOpenMode") }
    }

    /// "system" (follow macOS), "light" or "dark".
    static var appearance: String {
        get { d.string(forKey: "appearance") ?? "system" }
        set { d.set(newValue, forKey: "appearance"); applyAppearance() }
    }

    static func applyAppearance() {
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    static var editorFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}
