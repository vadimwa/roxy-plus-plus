import Foundation

struct SearchOptions {
    var query = ""
    var caseSensitive = false
    var wholeWord = false
    var regex = false
    var wrap = true
}

/// Line-start offsets (UTF-16) for fast line/column lookups.
final class LineIndex {
    private(set) var starts: [Int] = [0]

    var count: Int { starts.count }

    func rebuild(_ text: NSString) {
        var result = [0]
        let length = text.length
        let chunk = 65_536
        var buffer = [unichar](repeating: 0, count: chunk)
        var pos = 0
        while pos < length {
            let n = min(chunk, length - pos)
            buffer.withUnsafeMutableBufferPointer { p in
                text.getCharacters(p.baseAddress!, range: NSRange(location: pos, length: n))
            }
            for k in 0..<n where buffer[k] == 10 {
                result.append(pos + k + 1)
            }
            pos += n
        }
        starts = result
    }

    /// 0-based index of the line containing `location`.
    func line(containing location: Int) -> Int {
        var lo = 0
        var hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= location { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}

enum SearchEngine {
    static func regex(_ o: SearchOptions) throws -> NSRegularExpression {
        var pattern = o.regex ? o.query : NSRegularExpression.escapedPattern(for: o.query)
        if o.wholeWord { pattern = "\\b(?:" + pattern + ")\\b" }
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if !o.caseSensitive { options.insert(.caseInsensitive) }
        return try NSRegularExpression(pattern: pattern, options: options)
    }

    /// In regex mode, `\n`, `\t`, `\r` in the replacement become real characters and `$1` refers to groups.
    /// In normal mode, the replacement is used literally.
    static func template(_ replacement: String, regex: Bool) -> String {
        guard regex else { return NSRegularExpression.escapedTemplate(for: replacement) }
        var out = ""
        var it = replacement.makeIterator()
        while let c = it.next() {
            if c == "\\" {
                guard let n = it.next() else { out.append("\\\\"); break }
                switch n {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                default: out.append("\\"); out.append(n)
                }
            } else {
                out.append(c)
            }
        }
        return out
    }

    static func findNext(in text: String, from: Int, regex: NSRegularExpression, wrap: Bool) -> (range: NSRange, wrapped: Bool)? {
        let length = (text as NSString).length
        var start = min(max(0, from), length)
        if let m = regex.firstMatch(in: text, options: [], range: NSRange(location: start, length: length - start)) {
            if m.range.length == 0 && m.range.location == from && start < length {
                start += 1
                if let m2 = regex.firstMatch(in: text, options: [], range: NSRange(location: start, length: length - start)) {
                    return (m2.range, false)
                }
            } else {
                return (m.range, false)
            }
        }
        if wrap, let m = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: length)) {
            return (m.range, true)
        }
        return nil
    }

    static func findPrevious(in text: String, before: Int, regex: NSRegularExpression, wrap: Bool) -> (range: NSRange, wrapped: Bool)? {
        let length = (text as NSString).length
        let all = regex.matches(in: text, options: [], range: NSRange(location: 0, length: length))
        if let m = all.last(where: { $0.range.location < before && NSMaxRange($0.range) <= before }) {
            return (m.range, false)
        }
        if wrap, let m = all.last {
            return (m.range, true)
        }
        return nil
    }
}

/// Simple glob filter: "*.swift *.txt !node_modules !*.min.js"
struct GlobFilter {
    private var include: [NSRegularExpression] = []
    private var exclude: [NSRegularExpression] = []

    init(_ spec: String) {
        let tokens = spec.split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" }).map(String.init)
        for t in tokens {
            if t.hasPrefix("!") {
                if let re = GlobFilter.compile(String(t.dropFirst())) { exclude.append(re) }
            } else if let re = GlobFilter.compile(t) {
                include.append(re)
            }
        }
    }

    private static func compile(_ glob: String) -> NSRegularExpression? {
        guard !glob.isEmpty else { return nil }
        var p = "^"
        for ch in glob {
            switch ch {
            case "*": p += ".*"
            case "?": p += "."
            default: p += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        p += "$"
        return try? NSRegularExpression(pattern: p, options: [.caseInsensitive])
    }

    private static func matches(_ re: NSRegularExpression, _ name: String) -> Bool {
        re.firstMatch(in: name, options: [], range: NSRange(location: 0, length: (name as NSString).length)) != nil
    }

    func isExcluded(_ name: String) -> Bool {
        exclude.contains { GlobFilter.matches($0, name) }
    }

    func includesFile(_ name: String) -> Bool {
        if isExcluded(name) { return false }
        if include.isEmpty { return true }
        return include.contains { GlobFilter.matches($0, name) }
    }
}

struct SearchHit {
    let url: URL
    let line: Int        // 1-based
    let column: Int      // 0-based UTF-16 offset within the line
    let length: Int
    let preview: String
}

enum FileSearcher {
    struct Result {
        var hits: [SearchHit] = []
        var filesWithHits = 0
        var filesScanned = 0
        var truncated = false
    }

    static let maxHits = 20_000
    static let maxFileSize = 30_000_000
    static let alwaysSkippedDirs: Set<String> = [".git", ".svn", ".hg", ".DS_Store"]

    static func search(root: URL, regex: NSRegularExpression, filter: GlobFilter, recursive: Bool, includeHidden: Bool,
                       isCancelled: () -> Bool, progress: (Int) -> Void) -> Result {
        var result = Result()
        let fm = FileManager.default
        var options: FileManager.DirectoryEnumerationOptions = []
        if !recursive { options.insert(.skipsSubdirectoryDescendants) }
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: options) else { return result }

        while let url = enumerator.nextObject() as? URL {
            if isCancelled() { break }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = url.lastPathComponent
            if values?.isDirectory == true {
                if alwaysSkippedDirs.contains(name) || filter.isExcluded(name) { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true,
                  (values?.fileSize ?? 0) <= maxFileSize,
                  filter.includesFile(name),
                  let data = try? Data(contentsOf: url),
                  !FileIO.looksBinary(data) else { continue }

            result.filesScanned += 1
            if result.filesScanned % 50 == 0 { progress(result.filesScanned) }

            let text = LineEnding.normalize(FileIO.decode(data).0)
            let ns = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }
            result.filesWithHits += 1

            let index = LineIndex()
            index.rebuild(ns)
            for m in matches {
                let lineIdx = index.line(containing: m.range.location)
                let lineStart = index.starts[lineIdx]
                let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
                var preview = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if preview.count > 300 { preview = String(preview.prefix(300)) + "…" }
                result.hits.append(SearchHit(url: url, line: lineIdx + 1, column: m.range.location - lineStart,
                                             length: m.range.length, preview: preview))
                if result.hits.count >= maxHits { result.truncated = true; return result }
            }
        }
        return result
    }
}
