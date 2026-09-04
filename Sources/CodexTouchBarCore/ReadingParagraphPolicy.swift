import Foundation

public struct ReadingParagraph: Equatable {
    public var title: String
    public var text: String
    public var normalizedStartOffset: Int

    public init(title: String, text: String, normalizedStartOffset: Int) {
        self.title = title
        self.text = text
        self.normalizedStartOffset = normalizedStartOffset
    }
}

public enum ReadingParagraphPolicy {
    public static func paragraphs(in text: String, previewCharacters: Int = 28) -> [ReadingParagraph] {
        let normalizedLineEndings = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let rawParts = splitRawParagraphs(normalizedLineEndings)
        var paragraphs: [ReadingParagraph] = []
        var offset = 0

        for rawPart in rawParts {
            let paragraphText = collapsedText(rawPart)
            guard !paragraphText.isEmpty else { continue }
            let title = "\(paragraphs.count + 1) \(preview(paragraphText, maxCharacters: previewCharacters))"
            paragraphs.append(ReadingParagraph(
                title: title,
                text: paragraphText,
                normalizedStartOffset: offset
            ))
            offset += paragraphText.count + 1
        }

        return paragraphs
    }

    public static func pageIndex(forParagraph paragraph: ReadingParagraph, pages: [String]) -> Int {
        guard !pages.isEmpty else { return 0 }
        var offset = 0
        for (index, page) in pages.enumerated() {
            let endOffset = offset + page.count
            if paragraph.normalizedStartOffset <= endOffset {
                return index
            }
            offset = endOffset + 1
        }
        return pages.count - 1
    }

    private static func splitRawParagraphs(_ text: String) -> [String] {
        if text.range(of: #"\n\s*\n"#, options: .regularExpression) != nil {
            return text
                .replacingOccurrences(of: #"\n\s*\n+"#, with: "\u{001E}", options: .regularExpression)
                .components(separatedBy: "\u{001E}")
        }
        return text.components(separatedBy: "\n")
    }

    private static func collapsedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func preview(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters, maxCharacters > 1 else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: maxCharacters - 1)
        return "\(text[..<endIndex])..."
    }
}
