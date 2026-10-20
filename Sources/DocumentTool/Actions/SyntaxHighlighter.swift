import SwiftUI

/// A small, language-agnostic highlighter: good enough for nice-looking snippets,
/// not a full parser. Later rules win (comments beat strings beat keywords).
enum SyntaxHighlighter {
    enum Token {
        case keyword, string, number, comment, type, function, tag

        var color: Color {
            switch self {
            case .keyword: return Color(red: 0.80, green: 0.55, blue: 0.98)   // purple
            case .string: return Color(red: 0.65, green: 0.89, blue: 0.56)    // green
            case .number: return Color(red: 0.98, green: 0.70, blue: 0.45)    // orange
            case .comment: return Color(red: 0.45, green: 0.48, blue: 0.58)   // grey
            case .type: return Color(red: 0.98, green: 0.84, blue: 0.47)      // yellow
            case .function: return Color(red: 0.51, green: 0.71, blue: 0.99)  // blue
            case .tag: return Color(red: 0.96, green: 0.49, blue: 0.56)       // pink
            }
        }
    }

    static let keywords = [
        "let", "var", "const", "function", "return", "if", "else", "for", "while", "do", "import", "export",
        "from", "class", "struct", "enum", "func", "def", "async", "await", "public", "private", "protected",
        "static", "new", "true", "false", "nil", "null", "undefined", "type", "interface", "extends",
        "implements", "switch", "case", "break", "continue", "try", "catch", "throw", "throws", "guard", "in",
        "of", "as", "default", "self", "this", "super", "protocol", "extension", "package", "fn", "impl",
        "pub", "use", "mod", "match", "elif", "lambda", "yield", "with", "None", "True", "False", "where",
        "init", "override", "final", "void", "echo", "then", "fi", "end", "module", "require", "typeof",
        "instanceof", "readonly", "abstract", "namespace", "go", "defer", "chan", "select", "mut", "some", "any"
    ]

    /// Languages where `#` starts a comment.
    static let hashCommentExtensions: Set<String> = [
        "py", "rb", "sh", "zsh", "bash", "fish", "yml", "yaml", "toml", "r", "pl", "ex", "exs", "env",
        "ini", "dockerfile", "makefile"
    ]

    static func highlight(_ code: String, fileExtension ext: String) -> AttributedString {
        let ns = code as NSString
        var kinds = [Token?](repeating: nil, count: ns.length)

        func apply(_ pattern: String, _ token: Token, group: Int = 0, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            for match in regex.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
                let r = match.range(at: group)
                guard r.location != NSNotFound else { continue }
                for i in r.location..<(r.location + r.length) { kinds[i] = token }
            }
        }

        let keywordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"

        if ["html", "htm", "xml", "vue", "svelte", "astro", "jsx", "tsx"].contains(ext) {
            apply(#"</?([A-Za-z][A-Za-z0-9\-\.]*)"#, .tag, group: 1)
        }
        apply(#"\b[A-Z][A-Za-z0-9_]*\b"#, .type)
        apply(#"\b([a-zA-Z_][A-Za-z0-9_]*)\s*(?=\()"#, .function, group: 1)
        apply(keywordPattern, .keyword)
        apply(#"\b\d+(\.\d+)?\b"#, .number)
        // Strings and comments in one left-to-right pass, so "https://…" inside a string
        // isn't treated as a comment and quotes inside comments aren't strings.
        var comments = [#"/\*[\s\S]*?\*/"#, #"<!--[\s\S]*?-->"#]
        comments.append(hashCommentExtensions.contains(ext) ? #"#[^\n]*"# : #"//[^\n]*"#)
        if ext == "sql" || ext == "lua" { comments.append(#"--[^\n]*"#) }
        let strings = #""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`"#
        let combined = "(" + comments.joined(separator: "|") + ")|(" + strings + ")"
        apply(combined, .comment, group: 1)
        apply(combined, .string, group: 2)

        // Group equal runs into attributed segments.
        var result = AttributedString()
        var start = 0
        while start < ns.length {
            let kind = kinds[start]
            var end = start + 1
            while end < ns.length && kinds[end] == kind { end += 1 }
            var segment = AttributedString(ns.substring(with: NSRange(location: start, length: end - start)))
            if let kind { segment.foregroundColor = kind.color }
            result.append(segment)
            start = end
        }
        return result
    }
}
