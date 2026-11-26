import Foundation

/// Line ending style of a file. Text is always kept with "\n" in memory and converted on save.
enum LineEnding: String, Codable, CaseIterable {
    case lf, crlf, cr

    var label: String {
        switch self {
        case .lf: return "Unix (LF)"
        case .crlf: return "Windows (CR LF)"
        case .cr: return "Classic Mac (CR)"
        }
    }

    var sequence: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        }
    }

    /// Detects the first line ending used in the text (defaults to LF).
    static func detect(in text: String) -> LineEnding {
        var previousWasCR = false
        for byte in text.utf8 {
            if previousWasCR { return byte == 10 ? .crlf : .cr }
            if byte == 13 { previousWasCR = true } else if byte == 10 { return .lf }
        }
        return previousWasCR ? .cr : .lf
    }

    /// Converts all CR LF / CR line endings to LF.
    static func normalize(_ text: String) -> String {
        guard text.utf8.contains(13) else { return text }
        let m = NSMutableString(string: text)
        m.replaceOccurrences(of: "\r\n", with: "\n", options: .literal, range: NSRange(location: 0, length: m.length))
        m.replaceOccurrences(of: "\r", with: "\n", options: .literal, range: NSRange(location: 0, length: m.length))
        return m as String
    }
}

/// Encodings offered in the UI.
enum FileEncoding: String, Codable, CaseIterable {
    case utf8, utf8BOM, utf16LE, utf16BE, windows1252, latin1, macRoman

    var label: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf8BOM: return "UTF-8 with BOM"
        case .utf16LE: return "UTF-16 LE BOM"
        case .utf16BE: return "UTF-16 BE BOM"
        case .windows1252: return "Windows-1252 (ANSI)"
        case .latin1: return "ISO-8859-1 (Latin-1)"
        case .macRoman: return "Mac OS Roman"
        }
    }

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8, .utf8BOM: return .utf8
        case .utf16LE: return .utf16LittleEndian
        case .utf16BE: return .utf16BigEndian
        case .windows1252: return .windowsCP1252
        case .latin1: return .isoLatin1
        case .macRoman: return .macOSRoman
        }
    }

    var bom: [UInt8] {
        switch self {
        case .utf8BOM: return [0xEF, 0xBB, 0xBF]
        case .utf16LE: return [0xFF, 0xFE]
        case .utf16BE: return [0xFE, 0xFF]
        default: return []
        }
    }
}

struct LoadedText {
    let text: String          // normalized to LF
    let encoding: FileEncoding
    let lineEnding: LineEnding
}

struct EncodeError: LocalizedError {
    let encoding: FileEncoding
    var errorDescription: String? {
        "The text contains characters that can't be represented in \(encoding.label)."
    }
}

enum FileIO {
    /// Detects encoding from BOM / validity and decodes.
    static func decode(_ data: Data) -> (String, FileEncoding) {
        let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.starts(with: utf8BOM) {
            return (String(decoding: data.dropFirst(3), as: UTF8.self), .utf8BOM)
        }
        if data.starts(with: [0xFF, 0xFE]), let s = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
            return (s, .utf16LE)
        }
        if data.starts(with: [0xFE, 0xFF]), let s = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
            return (s, .utf16BE)
        }
        if let s = String(data: data, encoding: .utf8) { return (s, .utf8) }
        if let s = String(data: data, encoding: .windowsCP1252) { return (s, .windows1252) }
        if let s = String(data: data, encoding: .isoLatin1) { return (s, .latin1) }
        return (String(decoding: data, as: UTF8.self), .utf8)
    }

    /// Decodes using a specific encoding (used by "Reopen with Encoding").
    static func decode(_ data: Data, as encoding: FileEncoding) -> String? {
        var body = data
        if encoding == .utf8 || encoding == .utf8BOM {
            if data.starts(with: [0xEF, 0xBB, 0xBF]) { body = data.dropFirst(3) }
        } else if !encoding.bom.isEmpty, data.starts(with: encoding.bom) {
            body = data.dropFirst(encoding.bom.count)
        }
        return String(data: body, encoding: encoding.stringEncoding)
    }

    static func load(_ url: URL) throws -> LoadedText {
        let data = try Data(contentsOf: url)
        let (raw, enc) = decode(data)
        return LoadedText(text: LineEnding.normalize(raw), encoding: enc, lineEnding: LineEnding.detect(in: raw))
    }

    static func encode(_ text: String, encoding: FileEncoding, lineEnding: LineEnding) throws -> Data {
        var converted = text
        if lineEnding != .lf {
            let m = NSMutableString(string: text)
            m.replaceOccurrences(of: "\n", with: lineEnding.sequence, options: .literal, range: NSRange(location: 0, length: m.length))
            converted = m as String
        }
        guard let body = converted.data(using: encoding.stringEncoding, allowLossyConversion: false) else {
            throw EncodeError(encoding: encoding)
        }
        return Data(encoding.bom) + body
    }

    /// Heuristic used by Find in Files to skip binary files.
    static func looksBinary(_ data: Data) -> Bool {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return false }
        return data.prefix(8000).contains(0)
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
