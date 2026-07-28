import Foundation

/// The available ways ClipTidy can rewrite clipboard text.
enum CleanMode: String, CaseIterable {
    case smartReflow    = "Smart reflow"
    case joinParagraphs = "Join paragraphs"
    case trimLines      = "Trim lines"
    case oneLine        = "One line"
    case codeBlock      = "Code block"

    /// Short explanation shown next to the mode in the menu.
    var detail: String {
        switch self {
        case .smartReflow:    return "Strip quote bars, rejoin wrapped lines, keep list and paragraph breaks (best for chat)"
        case .joinParagraphs: return "Strip quote bars, merge wrap-broken lines into paragraphs"
        case .trimLines:      return "Strip quote bars and leading and trailing spaces, keep line breaks"
        case .oneLine:        return "Strip quote bars, collapse everything into a single line"
        case .codeBlock:      return "Strip quote bars, dedent, and wrap in ``` for code and logs"
        }
    }
}

/// Pure text transforms. No clipboard or UI knowledge lives here so the
/// logic stays easy to test and reuse.
enum Cleaner {

    static func clean(_ text: String, mode: CleanMode) -> String {
        // Every mode starts from gutter-free text. A quote bar copied out of a
        // terminal is never something you meant to keep, so no mode should make
        // you clean it by hand afterwards. Code block keeps "> " because there
        // it is usually a REPL prompt, not a quote.
        let prepared = stripQuoteGutters(text, allowAngleBracket: mode != .codeBlock)

        switch mode {
        case .smartReflow:    return smartReflow(prepared)
        case .joinParagraphs: return joinParagraphs(prepared)
        case .trimLines:      return trimLines(prepared)
        case .oneLine:        return oneLine(prepared)
        case .codeBlock:      return codeBlock(prepared)
        }
    }

    /// Rejoins lines the terminal wrapped and keeps the breaks that carry
    /// meaning: list items, blank lines, URLs on their own line, and a new
    /// sentence that starts after a finished one on a line the terminal did
    /// not fill to the wrap width. Quote gutters are already gone by here.
    static func smartReflow(_ text: String) -> String {
        let physical = normalize(text)
            .components(separatedBy: "\n")
            .map { stripTrailing($0) }

        // The longest line approximates the terminal's wrap width. A line
        // close to it was almost certainly wrapped mid-thought, so a sentence
        // ending there is not evidence of an intentional break.
        let maxLen = physical.map(\.count).max() ?? 0
        let wrapThreshold = maxLen >= 40 ? maxLen - 10 : Int.max

        var logical: [String] = []
        var current = ""
        var prevLen = 0

        func flush() {
            if !current.isEmpty { logical.append(current) }
            current = ""
        }

        for line in physical {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
                if !logical.isEmpty && logical.last != "" { logical.append("") }
                prevLen = 0
                continue
            }

            let startsNewLine = current.isEmpty
                || startsListItem(trimmed)
                || trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
                || (prevLen < wrapThreshold && endsSentence(current) && startsSentence(trimmed))

            if startsNewLine {
                flush()
                current = line  // keep the line's own indent for nested lists
            } else if endsWithURLToken(current) && looksLikeURLTail(trimmed) {
                current += trimmed  // rejoin a URL the wrap split mid-token
            } else {
                current += " " + trimmed
            }
            prevLen = line.count
        }
        flush()

        while logical.first == "" { logical.removeFirst() }
        while logical.last == "" { logical.removeLast() }
        return dedent(logical).joined(separator: "\n")
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

    // MARK: - Quote gutters

    /// Bar glyphs terminals and chat clients draw down the left of a quote.
    private static let barMarks: Set<Character> = ["▌", "▍", "▎", "▏", "▐", "▕", "│", "┃", "║", "❘", "❙", "❚"]

    private static func isQuoteMark(_ c: Character, allowAngleBracket: Bool) -> Bool {
        barMarks.contains(c) || (allowAngleBracket && c == ">")
    }

    /// Removes the quote gutter from every line that has one, along with the
    /// padding the gutter carries. The padding is measured across the whole
    /// selection and only the shared amount comes off, so a nested list inside
    /// a quote stays nested. Lines with no gutter are left exactly as they are,
    /// which is what makes a mixed copy (some quoted, some not) come out level.
    private static func stripQuoteGutters(_ text: String, allowAngleBracket: Bool) -> String {
        let lines = normalize(text).components(separatedBy: "\n")
        let split = lines.map { splitQuotePrefix($0, allowAngleBracket: allowAngleBracket) }
        guard split.contains(where: { $0.found }) else { return normalize(text) }

        // Blank quoted lines ("▎" on its own) carry no padding to learn from.
        let pads = split.filter { $0.found && !$0.body.isEmpty }.map(\.padding)
        let sharedPad = pads.min() ?? 0

        return zip(lines, split).map { original, piece -> String in
            guard piece.found else { return original }
            if piece.body.isEmpty { return "" }
            return String(repeating: " ", count: max(0, piece.padding - sharedPad)) + piece.body
        }.joined(separator: "\n")
    }

    /// Splits a line into its quote prefix and the rest. `padding` is the
    /// whitespace that followed the last marker; `body` has that whitespace
    /// already removed so the caller can decide how much to give back.
    ///
    /// A bar that shows up again inside the line is table or box art, not a
    /// gutter ("│ Name │ Age │"), so those lines come back untouched. Markdown's
    /// "> " gets no such veto because it never draws a table, and prose behind
    /// it can legitimately contain another ">".
    private static func splitQuotePrefix(
        _ line: String,
        allowAngleBracket: Bool
    ) -> (body: String, padding: Int, found: Bool) {
        var rest = Substring(line)
        var consumedBars: Set<Character> = []
        var found = false
        var padding = 0

        while true {
            var i = rest.startIndex
            while i < rest.endIndex, rest[i] == " " || rest[i] == "\t" { i = rest.index(after: i) }
            guard i < rest.endIndex, isQuoteMark(rest[i], allowAngleBracket: allowAngleBracket) else { break }

            while i < rest.endIndex, isQuoteMark(rest[i], allowAngleBracket: allowAngleBracket) {
                if barMarks.contains(rest[i]) { consumedBars.insert(rest[i]) }
                i = rest.index(after: i)
            }
            found = true
            padding = 0
            while i < rest.endIndex, rest[i] == " " || rest[i] == "\t" {
                padding += 1
                i = rest.index(after: i)
            }
            rest = rest[i...]
        }

        let body = stripTrailing(String(rest))
        if body.contains(where: { consumedBars.contains($0) }) { return (line, 0, false) }
        return (body, padding, found)
    }

    // MARK: - Smart reflow helpers

    /// True for lines that begin a list item or heading: "1.", "12)", "a.",
    /// "B)", "-", "*", "•", "## ".
    private static func startsListItem(_ s: String) -> Bool {
        guard let first = s.first else { return false }

        if "-*•◦▪‣·".contains(first), s.dropFirst().first == " " { return true }
        if first == "#" { return s.prefix(while: { $0 == "#" }).count <= 6 && s.drop(while: { $0 == "#" }).first == " " }

        let digits = s.prefix(while: { $0.isNumber })
        if (1...3).contains(digits.count) {
            let after = s.dropFirst(digits.count)
            if let p = after.first, p == "." || p == ")" {
                return after.dropFirst().first.map { $0 == " " } ?? true
            }
        }
        if digits.isEmpty, first.isLetter {
            let after = s.dropFirst()
            if let p = after.first, p == "." || p == ")" {
                return after.dropFirst().first.map { $0 == " " } ?? true
            }
        }
        return false
    }

    /// True when the text ends like a finished sentence, ignoring closing
    /// quotes and brackets after the punctuation.
    private static func endsSentence(_ s: String) -> Bool {
        var t = Substring(s)
        while let last = t.last, "\"'”’»)]".contains(last) { t = t.dropLast() }
        guard let last = t.last else { return false }
        return ".!?:…".contains(last)
    }

    /// True when the text starts like a fresh sentence.
    private static func startsSentence(_ s: String) -> Bool {
        guard let first = s.first else { return false }
        return first.isUppercase || first.isNumber || "\"'“‘«(".contains(first)
    }

    private static func endsWithURLToken(_ s: String) -> Bool {
        guard let last = s.split(separator: " ").last else { return false }
        return last.hasPrefix("http://") || last.hasPrefix("https://")
    }

    /// True when a line's first word looks like the continuation of a URL
    /// rather than prose, so it can be glued back without a space.
    private static func looksLikeURLTail(_ s: String) -> Bool {
        guard let first = s.split(separator: " ").first else { return false }
        return first.contains(where: { "/?=&#%-_~".contains($0) })
    }

    /// Removes the indentation shared by every non-empty line.
    private static func dedent(_ lines: [String]) -> [String] {
        let indents = lines.filter { !$0.isEmpty }.map { leadingWhitespaceCount($0) }
        guard let minIndent = indents.min(), minIndent > 0 else { return lines }
        return lines.map { $0.isEmpty ? $0 : String($0.dropFirst(minIndent)) }
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
