import Foundation

/// Text transformations offered in the Text menu. `rawValue` doubles as the menu item tag.
enum TextTool: Int, CaseIterable {
    case upper = 1, lower, title, invertCase
    case sortAsc, sortDesc, sortCaseInsensitive, sortNumeric, reverseLines, shuffleLines
    case uniqueLines, removeEmptyLines, trimTrailing, trimLeading, trimBoth, joinLines
    case tabsToSpaces, spacesToTabs
    case jsonPretty, jsonMinify
    case base64Encode, base64Decode, urlEncode, urlDecode, htmlEscape, htmlUnescape

    /// Line-based tools expand a partial selection to whole lines.
    var lineBased: Bool {
        switch self {
        case .sortAsc, .sortDesc, .sortCaseInsensitive, .sortNumeric, .reverseLines, .shuffleLines,
             .uniqueLines, .removeEmptyLines, .trimTrailing, .trimLeading, .trimBoth, .joinLines,
             .tabsToSpaces, .spacesToTabs:
            return true
        default:
            return false
        }
    }
}

struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum TextTools {
    static func splitLines(_ s: String) -> (lines: [String], trailingNewline: Bool) {
        var lines = s.components(separatedBy: "\n")
        let trailing = s.hasSuffix("\n")
        if trailing { lines.removeLast() }
        return (lines, trailing)
    }

    static func joinLines(_ lines: [String], trailingNewline: Bool) -> String {
        lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
    }

    private static func mapLines(_ s: String, _ f: ([String]) -> [String]) -> String {
        let (lines, trailing) = splitLines(s)
        return joinLines(f(lines), trailingNewline: trailing)
    }

    static func apply(_ tool: TextTool, to s: String, tabWidth: Int) throws -> String {
        switch tool {
        case .upper: return s.uppercased()
        case .lower: return s.lowercased()
        case .title: return s.capitalized
        case .invertCase:
            return String(s.map { c -> Character in
                let str = String(c)
                if str == str.uppercased() { return Character(str.lowercased().count == 1 ? str.lowercased() : str) }
                return Character(str.uppercased().count == 1 ? str.uppercased() : str)
            })

        case .sortAsc: return mapLines(s) { $0.sorted() }
        case .sortDesc: return mapLines(s) { $0.sorted(by: >) }
        case .sortCaseInsensitive:
            return mapLines(s) { $0.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
        case .sortNumeric:
            return mapLines(s) { $0.sorted { $0.compare($1, options: [.numeric, .caseInsensitive]) == .orderedAscending } }
        case .reverseLines: return mapLines(s) { Array($0.reversed()) }
        case .shuffleLines: return mapLines(s) { $0.shuffled() }
        case .uniqueLines:
            return mapLines(s) { lines in
                var seen = Set<String>()
                return lines.filter { seen.insert($0).inserted }
            }
        case .removeEmptyLines:
            return mapLines(s) { $0.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        case .trimTrailing:
            return mapLines(s) { $0.map { trimEnd($0) } }
        case .trimLeading:
            return mapLines(s) { $0.map { String($0.drop(while: { $0 == " " || $0 == "\t" })) } }
        case .trimBoth:
            return mapLines(s) { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
        case .joinLines:
            let (lines, trailing) = splitLines(s)
            let joined = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
            return joined + (trailing ? "\n" : "")

        case .tabsToSpaces:
            return mapLines(s) { $0.map { expandTabs($0, width: tabWidth) } }
        case .spacesToTabs:
            return mapLines(s) { $0.map { leadingSpacesToTabs($0, width: tabWidth) } }

        case .jsonPretty:
            try validateJSON(s)
            return formatJSON(s, indent: String(repeating: " ", count: tabWidth))
        case .jsonMinify:
            try validateJSON(s)
            return formatJSON(s, indent: nil)

        case .base64Encode:
            return Data(s.utf8).base64EncodedString()
        case .base64Decode:
            let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
            var padded = cleaned.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while padded.count % 4 != 0 { padded += "=" }
            guard let data = Data(base64Encoded: padded, options: .ignoreUnknownCharacters) else {
                throw ToolError(message: "The selection isn't valid Base64.")
            }
            guard let out = String(data: data, encoding: .utf8) else {
                throw ToolError(message: "The decoded data isn't UTF-8 text.")
            }
            return out
        case .urlEncode:
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        case .urlDecode:
            guard let out = s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else {
                throw ToolError(message: "The selection isn't valid percent-encoded text.")
            }
            return out
        case .htmlEscape:
            return s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        case .htmlUnescape:
            return htmlUnescape(s)
        }
    }

    // MARK: helpers

    static func trimEnd(_ s: String) -> String {
        var end = s.endIndex
        while end > s.startIndex {
            let prev = s.index(before: end)
            if s[prev] == " " || s[prev] == "\t" { end = prev } else { break }
        }
        return String(s[..<end])
    }

    static func expandTabs(_ line: String, width: Int) -> String {
        guard line.contains("\t") else { return line }
        var out = ""
        var col = 0
        for c in line {
            if c == "\t" {
                let n = width - (col % width)
                out += String(repeating: " ", count: n)
                col += n
            } else {
                out.append(c)
                col += 1
            }
        }
        return out
    }

    static func leadingSpacesToTabs(_ line: String, width: Int) -> String {
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        guard !leading.isEmpty else { return line }
        let columns = expandTabs(String(leading), width: width).count
        return String(repeating: "\t", count: columns / width)
            + String(repeating: " ", count: columns % width)
            + line.dropFirst(leading.count)
    }

    static func validateJSON(_ s: String) throws {
        do {
            _ = try JSONSerialization.jsonObject(with: Data(s.utf8), options: [.fragmentsAllowed])
        } catch {
            let ns = error as NSError
            let detail = (ns.userInfo[NSDebugDescriptionErrorKey] as? String) ?? ns.localizedDescription
            throw ToolError(message: "Invalid JSON: \(detail)")
        }
    }

    /// Re-indents JSON while preserving key order. `indent == nil` minifies.
    static func formatJSON(_ s: String, indent: String?) -> String {
        let chars = Array(s)
        var out = ""
        var level = 0
        var inString = false
        var escaped = false
        var i = 0

        func newline() {
            if let indent {
                out += "\n" + String(repeating: indent, count: level)
            }
        }

        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i += 1
                continue
            }
            switch c {
            case "\"":
                inString = true
                out.append(c)
            case "{", "[":
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, (c == "{" && chars[j] == "}") || (c == "[" && chars[j] == "]") {
                    out.append(c)
                    out.append(chars[j])
                    i = j + 1
                    continue
                }
                out.append(c)
                level += 1
                newline()
            case "}", "]":
                level = max(0, level - 1)
                newline()
                out.append(c)
            case ",":
                out.append(c)
                newline()
            case ":":
                out.append(c)
                if indent != nil { out.append(" ") }
            default:
                if !c.isWhitespace { out.append(c) }
            }
            i += 1
        }
        return out
    }

    static func htmlUnescape(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"]
        guard let re = try? NSRegularExpression(pattern: "&(#[xX]?[0-9a-fA-F]+|[a-zA-Z]+);") else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let body = ns.substring(with: m.range(at: 1))
            var replacement: String? = nil
            if body.hasPrefix("#") {
                let digits = body.dropFirst()
                let value: UInt32?
                if digits.hasPrefix("x") || digits.hasPrefix("X") { value = UInt32(digits.dropFirst(), radix: 16) }
                else { value = UInt32(digits, radix: 10) }
                if let v = value, let scalar = Unicode.Scalar(v) { replacement = String(Character(scalar)) }
            } else {
                replacement = named[body]
            }
            out += replacement ?? ns.substring(with: m.range)
            last = NSMaxRange(m.range)
        }
        out += ns.substring(from: last)
        return out
    }
}
