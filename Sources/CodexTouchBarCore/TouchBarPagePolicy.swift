import Foundation

public enum TouchBarPagePolicy {
    public static let defaultMaxCharacters = 52
    public static let pageIntervalSeconds: TimeInterval = 3.0
    public static let manualAdvanceMinimumInterval: TimeInterval = 0.35

    public static func pages(for text: String, maxCharacters: Int = defaultMaxCharacters) -> [String] {
        let normalized = normalizedText(text)
        guard !normalized.isEmpty else { return [""] }
        guard maxCharacters > 0 else { return [normalized] }

        var pages: [String] = []
        var remainder = normalized
        while remainder.count > maxCharacters {
            let limitIndex = remainder.index(remainder.startIndex, offsetBy: maxCharacters)
            let prefix = remainder[..<limitIndex]
            let splitIndex: String.Index
            if let spaceIndex = prefix.lastIndex(of: " "), spaceIndex > remainder.startIndex {
                splitIndex = spaceIndex
            } else {
                splitIndex = limitIndex
            }

            let page = String(remainder[..<splitIndex]).trimmingCharacters(in: .whitespaces)
            if !page.isEmpty {
                pages.append(page)
            }
            remainder = String(remainder[splitIndex...]).trimmingCharacters(in: .whitespaces)
        }

        if !remainder.isEmpty {
            pages.append(remainder)
        }
        return pages.isEmpty ? [""] : pages
    }

    public static func pages(
        for text: String,
        maxWidth: Double,
        measureWidth: (String) -> Double
    ) -> [String] {
        let normalized = normalizedText(text)
        guard !normalized.isEmpty else { return [""] }
        guard maxWidth > 0 else { return [normalized] }
        guard measureWidth(normalized) > maxWidth else { return [normalized] }

        var pages: [String] = []
        var remainder = normalized
        while !remainder.isEmpty {
            if measureWidth(remainder) <= maxWidth {
                pages.append(remainder)
                break
            }

            let splitIndex = measuredSplitIndex(in: remainder, maxWidth: maxWidth, measureWidth: measureWidth)
            let page = String(remainder[..<splitIndex]).trimmingCharacters(in: .whitespaces)
            if !page.isEmpty {
                pages.append(page)
            }
            remainder = String(remainder[splitIndex...]).trimmingCharacters(in: .whitespaces)
        }

        return pages.isEmpty ? [""] : pages
    }

    public static func nextPageIndex(currentIndex: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        return (currentIndex + 1) % pageCount
    }

    public static func canAdvanceAfterUserInteraction(
        now: TimeInterval,
        lastAdvanceAt: TimeInterval?,
        minimumInterval: TimeInterval = manualAdvanceMinimumInterval
    ) -> Bool {
        guard let lastAdvanceAt else { return true }
        return now - lastAdvanceAt >= minimumInterval
    }

    public static func automaticAdvanceDelay(
        now: TimeInterval,
        lastAdvanceAt: TimeInterval?,
        interval: TimeInterval = pageIntervalSeconds
    ) -> TimeInterval {
        guard let lastAdvanceAt else { return interval }
        return max(0, interval - (now - lastAdvanceAt))
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func measuredSplitIndex(
        in text: String,
        maxWidth: Double,
        measureWidth: (String) -> Double
    ) -> String.Index {
        var current = text.startIndex
        var lastFit = text.startIndex
        var bestBoundary: String.Index?

        while current < text.endIndex {
            let character = text[current]
            if character.isWhitespace,
               current > text.startIndex,
               measureWidth(String(text[..<current])) <= maxWidth {
                bestBoundary = current
            }

            let next = text.index(after: current)
            let candidate = String(text[..<next])
            guard measureWidth(candidate) <= maxWidth else { break }

            lastFit = next
            if isPreferredBreakPunctuation(character), next > text.startIndex {
                bestBoundary = next
            }
            current = next
        }

        if let bestBoundary, bestBoundary > text.startIndex {
            return bestBoundary
        }
        if lastFit > text.startIndex {
            return lastFit
        }
        return text.index(after: text.startIndex)
    }

    private static func isPreferredBreakPunctuation(_ character: Character) -> Bool {
        ",.;:!?，。！？；：、)]}）】》」』".contains(character)
    }
}
