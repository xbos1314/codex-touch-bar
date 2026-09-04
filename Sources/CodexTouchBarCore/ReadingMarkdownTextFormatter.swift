import Foundation

public enum ReadingMarkdownTextFormatter {
    public static func displayText(from text: String) -> String {
        let textWithoutFrontMatter = removeFrontMatter(from: normalizedLineEndings(text))
        let lines = textWithoutFrontMatter.components(separatedBy: "\n")
        var cleanedLines: [String] = []
        var isInsideFence = false

        for rawLine in lines {
            if isFenceMarker(rawLine) {
                isInsideFence.toggle()
                continue
            }

            let cleanedLine = isInsideFence
                ? rawLine.trimmingCharacters(in: .whitespaces)
                : cleanMarkdownLine(rawLine)
            append(cleanedLine, to: &cleanedLines)
        }

        while cleanedLines.first?.isEmpty == true {
            cleanedLines.removeFirst()
        }
        while cleanedLines.last?.isEmpty == true {
            cleanedLines.removeLast()
        }

        return cleanedLines.joined(separator: "\n")
    }

    private static func normalizedLineEndings(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func removeFrontMatter(from text: String) -> String {
        text.replacingOccurrences(
            of: #"(?s)^---\n.*?\n---\n?"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func isFenceMarker(_ line: String) -> Bool {
        line.range(of: #"^\s*(```+|~~~+)"#, options: .regularExpression) != nil
    }

    private static func cleanMarkdownLine(_ line: String) -> String {
        let withoutHTMLComments = line.replacingOccurrences(
            of: #"<!--.*?-->"#,
            with: "",
            options: .regularExpression
        )
        if withoutHTMLComments.range(of: #"^\s*[-*_]{3,}\s*$"#, options: .regularExpression) != nil {
            return ""
        }
        if withoutHTMLComments.range(of: #"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$"#, options: .regularExpression) != nil {
            return ""
        }

        let withoutBlockSyntax = withoutHTMLComments
            .replacingOccurrences(of: #"^\s{0,3}#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s{0,3}(>\s*)+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*\d+[\.)]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*\[[ xX]\]\s+"#, with: "", options: .regularExpression)

        return cleanInlineMarkdown(withoutBlockSyntax)
    }

    private static func cleanInlineMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*([^*\n]+)\*\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"__([^_\n]+)__"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"~~([^~\n]+)~~"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\*([^*\n]+)\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"<([^>\s]+@[^>\s]+)>"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"<(https?://[^>\s]+)>"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\|"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\\([\\`*_{}\[\]()#+\-.!>])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func append(_ line: String, to lines: inout [String]) {
        guard !line.isEmpty else {
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            return
        }
        lines.append(line)
    }
}
