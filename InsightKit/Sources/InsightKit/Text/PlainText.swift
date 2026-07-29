import Foundation

/// Turns light Markdown (the kind an LLM tends to emit) into clean, plain text
/// suitable for a dashboard label. The on-device Foundation model sometimes
/// wraps emphasis in `**bold**` or `*italic*`, adds `#` headings, ``code`` spans
/// or `- ` bullets even when told not to; this strips that formatting while
/// keeping the words, so the "Today" summary never shows raw `**` to the user.
public enum PlainText {

    /// Remove Markdown emphasis/heading/list/code markers from `input`,
    /// collapsing the leftover whitespace. Pure and deterministic.
    public static func strip(_ input: String) -> String {
        var lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines = lines.map { stripLine($0) }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLine(_ raw: String) -> String {
        var line = raw

        // Leading heading markers (## Title) and blockquotes (> quote).
        line = line.replacingOccurrences(
            of: "^\\s{0,3}#{1,6}\\s+", with: "", options: .regularExpression)
        line = line.replacingOccurrences(
            of: "^\\s{0,3}>\\s?", with: "", options: .regularExpression)

        // Leading list bullets: "- ", "* ", "+ ", "1. " → nothing.
        line = line.replacingOccurrences(
            of: "^\\s{0,3}([-*+]|\\d+\\.)\\s+", with: "", options: .regularExpression)

        // Inline emphasis: **bold**, __bold__, *italic*, _italic_, `code`.
        // Strip the markers, keep the inner text. Order matters: doubles first.
        for marker in ["**", "__"] {
            line = removeWrapping(marker, in: line)
        }
        for marker in ["*", "_", "`", "~~"] {
            line = removeWrapping(marker, in: line)
        }

        // Markdown links [text](url) → text.
        line = line.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^\\)]*\\)", with: "$1", options: .regularExpression)

        // Any stray remaining emphasis characters used unpaired.
        line = line.replacingOccurrences(of: "**", with: "")

        // Collapse runs of spaces produced by removals.
        line = line.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        return line.trimmingCharacters(in: .whitespaces)
    }

    /// Remove a paired inline marker (e.g. `**`) keeping the wrapped text.
    private static func removeWrapping(_ marker: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: marker)
        // Non-greedy content between two identical markers on the same line.
        let pattern = "\(escaped)(.+?)\(escaped)"
        return text.replacingOccurrences(
            of: pattern, with: "$1", options: .regularExpression)
    }
}
