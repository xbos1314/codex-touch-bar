import Foundation

public enum CodexDisplayTextFormatter {
    public static func displayText(from text: String) -> String {
        let withoutBlockMarkers = filteredDisplayLines(from: text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map(stripLineMarkdown)
            .joined(separator: "\n")

        return withoutBlockMarkers
            .replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"__([^_]+)__"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"~~([^~]+)~~"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"`{1,3}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\\([\\`*_{}\[\]()#+\-.!>])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func filteredDisplayLines(from text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var visibleLines: [String] = []
        var skippingVerificationBlock = false
        var skippingMemoryCitationBlock = false

        for line in normalized.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if skippingMemoryCitationBlock {
                if trimmed.contains("</oai-mem-citation>") {
                    skippingMemoryCitationBlock = false
                }
                continue
            }
            if trimmed.contains("<oai-mem-citation>") {
                skippingMemoryCitationBlock = !trimmed.contains("</oai-mem-citation>")
                continue
            }
            if trimmed.isEmpty {
                skippingVerificationBlock = false
                visibleLines.append(line)
                continue
            }

            if isImplementationSectionHeading(trimmed) {
                skippingVerificationBlock = isVerificationSectionHeading(trimmed)
                continue
            }

            if isFileReferenceLine(trimmed) {
                continue
            }

            if skippingVerificationBlock, isVerificationCommandLine(trimmed) {
                continue
            }

            skippingVerificationBlock = false
            visibleLines.append(line)
        }

        return visibleLines.joined(separator: "\n")
    }

    private static func stripLineMarkdown(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\s*`{3,}.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s{0,3}>\s?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*\d+[\.)]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*[-*_]{3,}\s*$"#, with: "", options: .regularExpression)
    }

    private static func isImplementationSectionHeading(_ text: String) -> Bool {
        let normalized = text
            .replacingOccurrences(of: "：", with: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let headings = [
            "改动",
            "修改",
            "修改内容",
            "变更",
            "变更内容",
            "涉及文件",
            "修改文件",
            "已修改",
            "文件",
            "验证",
            "已验证",
            "检查",
            "已检查"
        ]
        guard normalized.hasSuffix(":") else { return false }
        return headings.contains(String(normalized.dropLast()))
    }

    private static func isVerificationSectionHeading(_ text: String) -> Bool {
        let normalized = text
            .replacingOccurrences(of: "：", with: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "验证:"
            || normalized == "已验证:"
            || normalized == "检查:"
            || normalized == "已检查:"
    }

    private static func isFileReferenceLine(_ text: String) -> Bool {
        let body = text
            .replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*\d+[\.)]\s+"#, with: "", options: .regularExpression)
        if body.range(
            of: #"^\[[^\]]+\]\((?:<)?[^)]*\.[A-Za-z0-9]+:\d+(?:>)?\)(?:\s*[:：\-].*)?$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        return body.range(
            of: #"^`?(?:/|~|[A-Za-z0-9_.-]+/)[^`\s]*\.[A-Za-z0-9]+:\d+(?:[:：,\s\-]|$)"#,
            options: .regularExpression
        ) != nil
    }

    private static func isVerificationCommandLine(_ text: String) -> Bool {
        let body = text
            .replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*\d+[\.)]\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.hasPrefix("`")
            || body.range(
                of: #"^(swift|git|npm|pnpm|yarn|bun|xcodebuild|codesign|osascript|open|ditto|./)\b"#,
                options: .regularExpression
            ) != nil
    }
}
