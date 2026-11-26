import AppKit

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Colors that adapt to light / dark mode.
enum Theme {
    static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        dynamic(NSColor(hex: light), NSColor(hex: dark))
    }

    static let keyword = dynamic(0x0000C8, 0xFF7AB2)
    static let type = dynamic(0x0F68A0, 0x5DD8FF)
    static let string = dynamic(0xA31515, 0xFC6A5D)
    static let comment = dynamic(0x008000, 0x6BBF59)
    static let number = dynamic(0xC45A00, 0xD0BF69)
    static let tag = dynamic(0x0000A0, 0x6CB6FF)
    static let attribute = dynamic(0xB0000F, 0xE5C07B)
    static let heading = dynamic(0x0B4F79, 0xFFA14F)
    static let key = dynamic(0x7A1FA2, 0xC792EA)
    static let meta = dynamic(0x78492A, 0xFD8F3F)
    static let variable = dynamic(0x2D6A8A, 0x9CDCFE)
    static let error = dynamic(0xD32F2F, 0xFF6B6B)
    static let warning = dynamic(0xB26A00, 0xFFC66D)

    static let gutterBackground = dynamic(0xF3F3F3, 0x232323)
    static let gutterText = dynamic(0x9A9A9A, 0x6E6E6E)
    static let gutterCurrent = dynamic(0x333333, 0xD0D0D0)
    static let currentLine = dynamic(NSColor(hex: 0xE8F2FF), NSColor(hex: 0xFFFFFF, alpha: 0.06))
    static let markBackground = dynamic(NSColor(hex: 0xFFE14D, alpha: 0.65), NSColor(hex: 0xB89500, alpha: 0.55))
    static let tabBarBackground = dynamic(0xE4E4E4, 0x1E1E1E)
    static let tabSelected = dynamic(NSColor.white, NSColor(hex: 0x2B2B2B))
    static let tabHover = dynamic(NSColor(hex: 0x000000, alpha: 0.06), NSColor(hex: 0xFFFFFF, alpha: 0.06))
    static let separator = dynamic(0xC8C8C8, 0x3A3A3A)
    static let barBackground = dynamic(0xEDEDED, 0x262626)

    static func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .keyword: return keyword
        case .type: return type
        case .string: return string
        case .comment: return comment
        case .number: return number
        case .tag: return tag
        case .attribute: return attribute
        case .heading: return heading
        case .key: return key
        case .meta: return meta
        case .variable: return variable
        case .error: return error
        case .warning: return warning
        }
    }
}

/// Pre-compiled regexes for a language.
final class CompiledLanguage {
    let secondary: [(NSRegularExpression, NSColor)]
    let primary: NSRegularExpression?
    let primaryGroups: [(String, NSColor)]

    private static var cache: [String: CompiledLanguage] = [:]

    static func get(_ language: Language) -> CompiledLanguage {
        if let c = cache[language.id] { return c }
        let c = CompiledLanguage(language)
        cache[language.id] = c
        return c
    }

    private init(_ language: Language) {
        let opts: NSRegularExpression.Options = [.anchorsMatchLines]
        var compiledSecondary: [(NSRegularExpression, NSColor)] = []
        for (kind, pattern) in language.secondary {
            if let re = try? NSRegularExpression(pattern: pattern, options: opts) {
                compiledSecondary.append((re, Theme.color(for: kind)))
            } else {
                NSLog("%@", "MacPad: bad pattern in \(language.id): \(pattern)")
            }
        }
        secondary = compiledSecondary
        var groups: [(String, NSColor)] = []
        var parts: [String] = []
        for (i, rule) in language.primary.enumerated() {
            let name = "g\(i)"
            groups.append((name, Theme.color(for: rule.0)))
            parts.append("(?<\(name)>\(rule.1))")
        }
        primaryGroups = groups
        if parts.isEmpty {
            primary = nil
        } else {
            primary = try? NSRegularExpression(pattern: parts.joined(separator: "|"), options: opts)
            if primary == nil { NSLog("%@", "MacPad: bad primary pattern in \(language.id)") }
        }
    }
}

enum Highlighter {
    /// Paints syntax colors as temporary attributes (they don't touch the text storage or undo stack).
    static func highlight(_ layoutManager: NSLayoutManager, text: String, range: NSRange, language: Language) {
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        guard range.length > 0, language.id != Language.plain.id else { return }
        let compiled = CompiledLanguage.get(language)

        for (re, color) in compiled.secondary {
            re.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let r = match?.range, r.length > 0 else { return }
                layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: r)
            }
        }
        if let primary = compiled.primary {
            primary.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                for (name, color) in compiled.primaryGroups {
                    let r = match.range(withName: name)
                    if r.location != NSNotFound {
                        if r.length > 0 {
                            layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: r)
                        }
                        break
                    }
                }
            }
        }
    }
}
