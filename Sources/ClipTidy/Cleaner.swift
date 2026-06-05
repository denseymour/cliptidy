import Foundation

/// The available ways ClipTidy can rewrite clipboard text.
enum CleanMode: String, CaseIterable {
    case joinParagraphs = "Join paragraphs"
    case trimLines      = "Trim lines"
    case oneLine        = "One line"
    case codeBlock      = "Code block"

    /// Short explanation shown next to the mode in the menu.
    var detail: String {
        switch self {
        case .joinParagraphs: return "Merge wrap-broken lines into paragraphs (best for chat)"
        case .trimLines:      return "Strip leading and trailing spaces, keep line breaks"
        case .oneLine:        return "Collapse everything into a single line"
        case .codeBlock:      return "Dedent and wrap in ``` for code and logs"
        }
    }
}

/// Pure text transforms. No clipboard or UI knowledge lives here so the
/// logic stays easy to test and reuse.
enum Cleaner {

    static func clean(_ text: String, mode: CleanMode) -> String {
        switch mode {
        case .joinParagraphs: return joinParagraphs(text)
        case .trimLines:      return trimLines(text)
        case .oneLine:        return oneLine(text)
        case .codeBlock:      return codeBlock(text)
        }
    }

    /// Trims every line and collapses runs of blank lines down to one.
    static func trimLines(_ text: String) -> String {
        let lines = normalize(text)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var result = lines.joined(separator: "\n")
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Joins consecutive non-blank lines into one paragraph, keeping blank
    /// lines as paragraph breaks. This is the fix for terminal text that the
    /// screen broke into rows.
    static func joinParagraphs(_ text: String) -> String {
        var paragraphs: [String] = []
        var current: [String] = []

        func flush() {
            if !current.isEmpty {
                paragraphs.append(current.joined(separator: " "))
                current.removeAll()
            }
        }

        for raw in normalize(text).components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush() } else { current.append(line) }
        }
        flush()
        return paragraphs.joined(separator: "\n\n")
    }

    /// Everything becomes a single space-separated line.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Removes the common left padding the terminal added, keeps real
    /// indentation, and wraps the result in a fenced code block.
    static func codeBlock(_ text: String) -> String {
        let lines = normalize(text)
            .components(separatedBy: "\n")
            .map { stripTrailing($0) }

        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonEmpty.isEmpty else { return "" }

        let minIndent = nonEmpty.map { leadingWhitespaceCount($0) }.min() ?? 0
        let dedented = lines
            .map { $0.count >= minIndent ? String($0.dropFirst(minIndent)) : $0 }
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)

        return "```\n" + dedented + "\n```"
    }

    // MARK: - Helpers

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func stripTrailing(_ line: String) -> String {
        var l = line
        while let last = l.last, last == " " || last == "\t" { l.removeLast() }
        return l
    }

    private static func leadingWhitespaceCount(_ line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " || ch == "\t" { count += 1 } else { break }
        }
        return count
    }
}
