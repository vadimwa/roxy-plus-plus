import Foundation

enum TokenKind {
    case keyword, type, string, comment, number, tag, attribute, heading, key, meta, variable, error, warning
}

/// A regex-based language definition.
/// - `primary` rules (comments, strings) are combined into one alternation and scanned left-to-right,
///   so whichever starts first wins; they are painted last and override `secondary` rules.
/// - `secondary` rules (keywords, numbers, …) are painted first.
struct Language {
    let id: String
    let name: String
    var extensions: [String] = []
    var fileNames: [String] = []
    var shebangs: [String] = []
    var primary: [(TokenKind, String)] = []
    var secondary: [(TokenKind, String)] = []
    var lineComment: String? = nil
    var blockComment: (String, String)? = nil
    var indentAfterColon = false

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    static func make(_ id: String, _ name: String, _ configure: (inout Language) -> Void) -> Language {
        var l = Language(id: id, name: name)
        configure(&l)
        return l
    }
}

// MARK: - Pattern helpers

private func words(_ list: String, caseInsensitive: Bool = false) -> String {
    let escaped = list.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
    return (caseInsensitive ? "(?i)" : "") + "\\b(?:" + escaped.joined(separator: "|") + ")\\b"
}

private enum P {
    static let dq = #""(?:[^"\\\n]|\\.)*"?"#
    static let sq = #"'(?:[^'\\\n]|\\.)*'?"#
    static let dqMulti = #""(?:[^"\\]|\\.)*"?"#
    static let backtick = #"`(?:[^`\\]|\\.)*`?"#
    static let tripleDQ = "\"\"\"[\\s\\S]*?(?:\"\"\"|\\z)"
    static let tripleSQ = "'''[\\s\\S]*?(?:'''|\\z)"
    static let slashComment = #"//.*"#
    static let hashComment = #"#.*"#
    static let shellComment = #"(?<![\w$#{])#.*"#
    static let dashComment = #"--.*"#
    static let cBlock = #"/\*[\s\S]*?(?:\*/|\z)"#
    static let number = #"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#
}

// MARK: - Definitions

extension Language {
    static let plain = Language(id: "text", name: "Plain Text")

    static let all: [Language] = [
        plain,

        .make("c", "C / C++ / Objective-C") { l in
            l.extensions = ["c", "h", "cpp", "cc", "cxx", "hpp", "hh", "hxx", "m", "mm", "ino"]
            l.lineComment = "//"; l.blockComment = ("/*", "*/")
            l.primary = [(.comment, P.cBlock), (.comment, P.slashComment), (.string, P.dq), (.string, P.sq)]
            l.secondary = [
                (.number, P.number),
                (.type, words("size_t ssize_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t uintptr_t std string vector map set unordered_map unique_ptr shared_ptr NULL FILE BOOL YES NO id nil NSString NSArray NSDictionary")),
                (.keyword, words("auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while class namespace template typename public private protected virtual override final new delete this throw try catch using operator friend explicit constexpr nullptr true false bool static_cast dynamic_cast reinterpret_cast const_cast noexcept decltype mutable self super @interface @implementation @end @property @synthesize")),
                (.meta, #"^\s*#\s*\w+"#),
            ]
        },

        .make("csharp", "C#") { l in
            l.extensions = ["cs", "csx"]
            l.lineComment = "//"; l.blockComment = ("/*", "*/")
            l.primary = [(.comment, P.cBlock), (.comment, P.slashComment), (.string, #"@"(?:[^"]|"")*"?"#), (.string, #"\$?"(?:[^"\\\n]|\\.)*"?"#), (.string, P.sq)]
            l.secondary = [
                (.number, P.number),
                (.type, words("String Int32 Int64 List Dictionary Task Console Exception IEnumerable Guid DateTime Action Func")),
                (.keyword, words("abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using virtual void volatile while var async await get set value yield record init required partial where dynamic nameof")),
                (.meta, #"^\s*#\w+"#),
            ]
        },

        .make("css", "CSS / SCSS / Less") { l in
            l.extensions = ["css", "scss", "sass", "less"]
            l.lineComment = nil; l.blockComment = ("/*", "*/")
            l.primary = [(.comment, P.cBlock), (.comment, #"(?<![:\w])//.*"#), (.string, P.dq), (.string, P.sq)]
            l.secondary = [
                (.attribute, #"[\w-]+(?=\s*:[^:])"#),
                (.number, #"#[0-9a-fA-F]{3,8}\b"#),
                (.number, #"(?<![\w-])-?\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|vmin|vmax|s|ms|deg|fr|pt|ch|ex)?\b"#),
                (.keyword, #"@[\w-]+|!important"#),
                (.variable, #"\$[\w-]+|--[\w-]+"#),
            ]
        },

        .make("dockerfile", "Dockerfile") { l in
            l.extensions = ["dockerfile"]
            l.fileNames = ["Dockerfile", "Containerfile"]
            l.lineComment = "#"
            l.primary = [(.comment, #"^\s*#.*"#), (.string, P.dq), (.string, P.sq)]
            l.secondary = [
                (.keyword, #"(?i)^\s*(?:FROM|RUN|CMD|LABEL|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL|MAINTAINER)\b"#),
                (.keyword, #"(?i)\bAS\b"#),
                (.variable, #"\$\{?\w+\}?"#),
            ]
        },

        .make("go", "Go") { l in
            l.extensions = ["go"]
            l.lineComment = "//"; l.blockComment = ("/*", "*/")
            l.primary = [(.comment, P.cBlock), (.comment, P.slashComment), (.string, P.backtick), (.string, P.dq), (.string, P.sq)]
            l.secondary = [
                (.number, P.number),
                (.type, words("int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 uintptr float32 float64 complex64 complex128 byte rune string bool error any make new len cap append copy delete panic recover print println close")),
                (.keyword, words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil iota")),
            ]
        },

        .make("html", "HTML / XML") { l in
            l.extensions = ["html", "htm", "xhtml", "xml", "svg", "plist", "xsd", "xsl", "xslt", "xaml", "csproj", "vbproj", "props", "targets", "storyboard", "xib", "rss", "atom", "vue", "kml", "gpx"]
            l.blockComment = ("<!--", "-->")
            l.primary = [(.comment, #"<!--[\s\S]*?(?:-->|\z)"#), (.string, #"<!\[CDATA\[[\s\S]*?(?:\]\]>|\z)"#)]
            l.secondary = [
                (.tag, #"</?[A-Za-z_][\w:.-]*|/?>"#),
                (.attribute, #"(?<=\s)[A-Za-z_:@][\w:.-]*(?=\s*=)"#),
                (.string, #"(?<==)\s*(?:"[^"]*"|'[^']*')"#),
                (.meta, #"<![A-Za-z][^>]*>|<\?[\s\S]*?\?>|&#?\w+;"#),
            ]
        },

        .make("ini", "INI / TOML / Properties") { l in
            l.extensions = ["ini", "cfg", "conf", "toml", "properties", "env", "editorconfig", "gitconfig", "gitattributes", "npmrc"]
            l.fileNames = [".env", ".gitconfig", ".editorconfig", ".npmrc", ".gitattributes"]
            l.lineComment = "#"
            l.primary = [(.comment, #"^\s*[;#].*"#), (.string, P.dq), (.string, P.sq)]
            l.secondary = [
                (.heading, #"^\s*\[.*\]"#),
                (.key, #"^\s*[\w.\-"]+(?=\s*[=:])"#),
                (.keyword, words("true false yes no on off null", caseInsensitive: true)),
                (.number, P.number),
            ]
        },

        .make("java", "Java / Kotlin / Scala") { l in
            l.extensions = ["java", "kt", "kts", "scala", "groovy", "gradle"]
            l.lineComment = "//"; l.blockComment = ("/*", "*/")
            l.primary = [(.comment, P.cBlock), (.comment, P.slashComment), (.string, P.tripleDQ), (.string, P.dq), (.string, P.sq)]
            l.secondary = [
                (.number, P.number),
                (.type, words("String Integer Long Double Boolean Object List Map Set ArrayList HashMap Optional Exception RuntimeException Unit Any Int Float Char Byte Short Array")),
                (.keyword, words("abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while var val fun object when is in out override open data sealed companion lateinit suspend internal true false null record yield def trait")),
                (.meta, #"@\w+"#),
            ]
        },

        .make("javascript", "JavaScript / TypeScript") { l in
            l.extensions = ["js", "mjs", "cjs", "jsx", "ts", "mts", "cts", "tsx"]
            l.shebangs = ["node", "deno", "bun"]
            l.lineComment = "//"; l.blockComment = ("/*", "*/")
            l.primary = [(.comment, P.cBlock), (.comment, P.slashComment), (.string, P.backtick), (.string, P.dq), (.string, P.sq)]
            l.secondary = [
                (.number, P.number),
                (.type, words("true false null undefined NaN Infinity number string boolean any unknown never object void Array Promise Map Set WeakMap Object String Number Boolean Symbol BigInt console window document JSON Math Date Error RegExp process require module exports")),
                (.keyword, words("break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new return super switch this throw try typeof var while with yield async await of static get set from as interface type enum implements private public protected readonly declare namespace abstract keyof satisfies")),
            ]
        },

        .make("json", "JSON") { l in
            l.extensions = ["json", "jsonc", "json5", "geojson", "har", "ipynb", "webmanifest"]
            l.fileNames = [".prettierrc", ".eslintrc", ".babelrc"]
            l.lineComment = "//"; l.blockComment = ("/*", "*/")
            l.primary = [(.comment, P.cBlock), (.comment, P.slashComment), (.key, #""(?:[^"\\\n]|\\.)*"(?=\s*:)"#), (.string, P.dq)]
            l.secondary = [
                (.number, #"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#),
                (.keyword, words("true false null")),
            ]
        },

        .make("log", "Log file") { l in
            l.extensions = ["log", "out"]
            l.secondary = [
                (.number, #"\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\b|\b\d{2}:\d{2}:\d{2}(?:[.,]\d+)?\b"#),
                (.comment, #"(?i)\b(?:DEBUG|TRACE|VERBOSE)\b"#),
                (.keyword, #"(?i)\b(?:INFO|NOTICE)\b"#),
                (.warning, #"(?i)\b(?:WARN|WARNING)\b"#),
                (.error, #"(?i)\b(?:ERROR|ERR|FATAL|CRITICAL|SEVERE|EXCEPTION|FAIL(?:ED|URE)?|PANIC)\b"#),
                (.string, P.dq),
            ]
        },

        .make("makefile", "Makefile") { l in
            l.extensions = ["mk", "mak"]
            l.fileNames = ["Makefile", "makefile", "GNUmakefile"]
            l.lineComment = "#"
            l.primary = [(.comment, P.hashComment)]
            l.secondary = [
                (.heading, #"^[\w.%/ -]+(?=\s*::?(?!=))"#),
                (.variable, #"\$[({][^)}]*[)}]|\$[\w@<^?*%]"#),
                (.keyword, words("ifeq ifneq ifdef ifndef else endif include define endef export override")),
            ]
        },

        .make("markdown", "Markdown") { l in
            l.extensions = ["md", "markdown", "mdown", "mkd"]
            l.blockComment = ("<!--", "-->")
            l.primary = [
                (.string, "^ {0,3}(?:```|~~~)[\\s\\S]*?(?:^ {0,3}(?:```|~~~)[ \\t]*$|\\z)"),
                (.string, #"`[^`\n]+`"#),
                (.comment, #"<!--[\s\S]*?(?:-->|\z)"#),
                (.meta, #"\A---\n[\s\S]*?\n---$"#),
            ]
            l.secondary = [
                (.variable, #"(?<![*\w])\*(?=[^\s*])[^*\n]+?(?<=[^\s*])\*(?![*\w])|(?<![_\w])_(?=[^\s_])[^_\n]+?(?<=[^\s_])_(?![_\w])"#),
                (.keyword, #"\*\*[^*\n]+\*\*|__[^_\n]+__"#),
                (.comment, #"~~[^~\n]+~~"#),
                (.attribute, #"!?\[[^\]\n]*\]\([^)\n]*\)|<https?://[^>\s]+>|(?<![(<"])\bhttps?://[^\s)>\]]+"#),
                (.number, #"^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s)?"#),
                (.comment, #"^\s*>.*"#),
                (.meta, #"^ {0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$|\|"#),
                (.heading, #"^ {0,3}#{1,6}(?:\s.*)?$|^ {0,3}(?:=+|-+)\s*$"#),
            ]
        },

        .make("php", "PHP") { l in
            l.extensions = ["php", "phtml", "php3", "php4", "php5", "phps"]
            l.shebangs = ["php"]
            l.lineComment = "//"; l.blockComment = ("/*", "*/")
            l.primary = [(.comment, P.cBlock), (.comment, P.slashComment), (.comment, P.shellComment), (.string, P.dqMulti), (.string, P.sq)]
            l.secondary = [
                (.number, P.number),
                (.keyword, words("abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield true false null", caseInsensitive: true)),
                (.variable, #"\$\w+"#),
                (.meta, #"<\?php|<\?=|\?>"#),
            ]
        },

        .make("python", "Python") { l in
            l.extensions = ["py", "pyw", "pyi", "pyx", "gyp"]
            l.fileNames = ["SConstruct", "SConscript"]
            l.shebangs = ["python"]
            l.lineComment = "#"
            l.indentAfterColon = true
            l.primary = [
                (.string, "(?i:[rbuf]{0,2})" + P.tripleDQ),
                (.string, "(?i:[rbuf]{0,2})" + P.tripleSQ),
                (.comment, P.hashComment),
                (.string, "(?i:[rbuf]{0,2})" + P.dq),
                (.string, "(?i:[rbuf]{0,2})" + P.sq),
            ]
            l.secondary = [
                (.number, P.number),
                (.type, words("int float str bool list dict set frozenset tuple bytes bytearray object type len range print open super isinstance issubclass enumerate zip map filter sorted reversed any all min max sum abs repr input iter next getattr setattr hasattr Exception ValueError TypeError KeyError IndexError")),
                (.keyword, words("False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case self cls")),
                (.meta, #"^\s*@[\w.]+"#),
            ]
        },

        .make("ruby", "Ruby") { l in
            l.extensions = ["rb", "rake", "gemspec", "ru", "erb"]
            l.fileNames = ["Gemfile", "Rakefile", "Podfile", "Fastfile", "Vagrantfile", "Brewfile"]
            l.shebangs = ["ruby"]
            l.lineComment = "#"
            l.primary = [(.comment, #"^=begin[\s\S]*?(?:^=end|\z)"#), (.comment, P.shellComment), (.string, P.dqMulti), (.string, P.sq)]
            l.secondary = [
                (.number, P.number),
                (.type, #":\w+|\b[A-Z]\w*"#),
                (.keyword, words("BEGIN END alias and begin break case class def do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield require require_relative attr_accessor attr_reader attr_writer puts lambda proc private protected public")),
                (.variable, #"@{1,2}\w+|\$\w+"#),
            ]
        },

        .make("rust", "Rust") { l in
            l.extensions = ["rs"]
            l.lineComment = "//"; l.blockComment = ("/*", "*/")
            l.primary = [(.comment, P.cBlock), (.comment, P.slashComment), (.string, ##"\br#*"[\s\S]*?"#*"##), (.string, P.dqMulti)]
            l.secondary = [
                (.number, P.number),
                (.type, words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Some None Ok Err Box Rc Arc HashMap HashSet")),
                (.keyword, words("as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while")),
                (.meta, #"#!?\[[^\]\n]*\]|\b\w+!"#),
            ]
        },

        .make("shell", "Shell / Bash / Zsh") { l in
            l.extensions = ["sh", "bash", "zsh", "ksh", "fish", "command", "tool"]
            l.fileNames = [".bashrc", ".bash_profile", ".zshrc", ".zprofile", ".profile", ".zshenv", ".bash_aliases"]
            l.shebangs = ["bash", "zsh", "/sh", " sh", "ksh", "fish"]
            l.lineComment = "#"
            l.primary = [(.comment, P.shellComment), (.string, P.dqMulti), (.string, #"'[^']*'?"#)]
            l.secondary = [
                (.number, #"\b\d+\b"#),
                (.type, words("echo printf cd pwd read test cat grep sed awk ls cp mv rm mkdir chmod chown find xargs curl wget git sudo brew npm open tar ssh scp")),
                (.keyword, words("if then else elif fi case esac for while until do done in function select return break continue exit export local readonly declare unset shift source alias set trap eval exec time")),
                (.variable, #"\$\{[^}\n]*\}|\$\([^)\n]*\)|\$[\w@#?$!*-]"#),
            ]
        },

        .make("sql", "SQL") { l in
            l.extensions = ["sql", "psql", "mysql", "ddl", "dml", "hql", "bq"]
            l.lineComment = "--"; l.blockComment = ("/*", "*/")
            l.primary = [(.comment, P.cBlock), (.comment, P.dashComment), (.string, #"'(?:[^']|'')*'?"#), (.key, #""[^"\n]*"|`[^`\n]*`"#)]
            l.secondary = [
                (.number, P.number),
                (.type, words("int integer bigint smallint tinyint varchar nvarchar char text date datetime timestamp time interval boolean bool decimal numeric float real double serial bigserial json jsonb uuid array struct string int64 float64 count sum avg min max coalesce ifnull nullif now concat substring lower upper trim round cast", caseInsensitive: true)),
                (.keyword, words("select from where insert into values update set delete create table alter drop index view and or not null is in like ilike between join inner left right outer full cross on as group by order having limit offset distinct union all case when then else end exists primary key foreign references default constraint unique check begin commit rollback transaction with recursive returning asc desc if replace truncate grant revoke database schema procedure function trigger declare over partition qualify window row rows range unnest merge using matched", caseInsensitive: true)),
                (.variable, #"[@:]\w+"#),
            ]
        },

        .make("swift", "Swift") { l in
            l.extensions = ["swift"]
            l.lineComment = "//"; l.blockComment = ("/*", "*/")
            l.primary = [(.comment, P.cBlock), (.comment, P.slashComment), (.string, P.tripleDQ), (.string, P.dq)]
            l.secondary = [
                (.number, P.number),
                (.type, words("Int Double Float String Bool Character Array Dictionary Set Optional Void UInt Int8 Int16 Int32 Int64 UInt8 UInt16 UInt32 UInt64 CGFloat CGRect CGPoint CGSize Data Date URL Error Result Never Any AnyObject")),
                (.keyword, words("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw switch where while as await async false is nil self Self super throws true try some any actor nonisolated mutating override final lazy weak unowned convenience required dynamic optional indirect consuming borrowing")),
                (.meta, #"@\w+|#\w+"#),
            ]
        },

        .make("yaml", "YAML") { l in
            l.extensions = ["yml", "yaml"]
            l.fileNames = [".clang-format", ".yamllint"]
            l.lineComment = "#"
            l.primary = [(.comment, #"(?:^|(?<=\s))#.*"#), (.string, P.dq), (.string, P.sq)]
            l.secondary = [
                (.number, P.number),
                (.key, #"^\s*(?:-\s+)?[^\s#:'"][^#:\n]*?(?=\s*:(?:\s|$))"#),
                (.keyword, words("true false yes no null on off", caseInsensitive: true)),
                (.meta, #"^---|^\.\.\.|&\w+|\*\w+|![\w!]+"#),
            ]
        },
    ]

    static func byID(_ id: String) -> Language {
        all.first { $0.id == id } ?? plain
    }

    /// Picks a language from the file name / extension, or from a shebang / XML prolog in the text.
    static func detect(url: URL?, text: String) -> Language {
        if let url {
            let name = url.lastPathComponent
            if let l = all.first(where: { $0.fileNames.contains(name) }) { return l }
            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty, let l = all.first(where: { $0.extensions.contains(ext) }) { return l }
            if name.lowercased().hasPrefix("dockerfile") { return byID("dockerfile") }
        }
        let firstLine = text.prefix(200).split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        if firstLine.hasPrefix("#!") {
            for l in all where l.shebangs.contains(where: { firstLine.contains($0) }) { return l }
        }
        if firstLine.hasPrefix("<?xml") || firstLine.lowercased().hasPrefix("<!doctype html") { return byID("html") }
        return plain
    }
}
