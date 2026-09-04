import Foundation

public enum CodexSessionSelectionMode: Equatable, Sendable {
    case automaticLatest
    case locked(URL)
}

public enum CodexSessionSelectionPolicy {
    public static func selectedSession(
        from sessions: [CodexSessionFile],
        mode: CodexSessionSelectionMode
    ) -> CodexSessionFile? {
        let sorted = sessions.sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            return $0.url.lastPathComponent > $1.url.lastPathComponent
        }

        switch mode {
        case .automaticLatest:
            return sorted.first
        case .locked(let url):
            return sorted.first { $0.url == url } ?? sorted.first
        }
    }

    public static func validatedMode(
        _ mode: CodexSessionSelectionMode,
        sessions: [CodexSessionFile]
    ) -> CodexSessionSelectionMode {
        guard case .locked(let url) = mode else { return mode }
        return sessions.contains { $0.url == url } ? mode : .automaticLatest
    }
}

public enum CodexSessionSelectorSignature {
    public static func value(
        sessions: [CodexSessionFile],
        selectionMode: CodexSessionSelectionMode
    ) -> String {
        let mode: String
        switch selectionMode {
        case .automaticLatest:
            mode = "auto"
        case .locked(let url):
            mode = "locked:\(url.path)"
        }

        let sessionPart = sessions.map {
            "\($0.url.path)|\($0.displayName)"
        }.joined(separator: ";")
        return "\(mode)#\(sessionPart)"
    }
}

public enum TouchBarSessionSelectorLayout {
    public static let minimumItemWidth: Double = 72
    public static let itemWidth: Double = 132
    public static let itemGap: Double = 6
    public static let horizontalPadding: Double = 8

    public static func contentWidth(itemWidths: [Double]) -> Double {
        let widths = itemWidths.isEmpty ? [minimumItemWidth] : itemWidths
        return horizontalPadding * 2
            + widths.reduce(0, +)
            + Double(max(0, widths.count - 1)) * itemGap
    }

    public static func contentWidth(sessionCount: Int) -> Double {
        let itemCount = max(1, sessionCount + 1)
        return horizontalPadding * 2
            + Double(itemCount) * itemWidth
            + Double(max(0, itemCount - 1)) * itemGap
    }

    public static func requiresHorizontalScrolling(itemWidths: [Double], viewportWidth: Double) -> Bool {
        contentWidth(itemWidths: itemWidths) > viewportWidth
    }

    public static func requiresHorizontalScrolling(sessionCount: Int, viewportWidth: Double) -> Bool {
        contentWidth(sessionCount: sessionCount) > viewportWidth
    }

    public static func itemFrames(itemWidths: [Double], itemHeight: Double) -> [TouchBarSessionSelectorItemFrame] {
        let widths = itemWidths.isEmpty ? [minimumItemWidth] : itemWidths
        var nextX = horizontalPadding
        return widths.map { width in
            let measuredWidth = max(minimumItemWidth, width)
            defer { nextX += measuredWidth + itemGap }
            return TouchBarSessionSelectorItemFrame(
                x: nextX,
                y: 0,
                width: measuredWidth,
                height: itemHeight
            )
        }
    }

    public static func itemFrames(sessionCount: Int, itemHeight: Double) -> [TouchBarSessionSelectorItemFrame] {
        let itemCount = max(1, sessionCount + 1)
        return (0..<itemCount).map { index in
            TouchBarSessionSelectorItemFrame(
                x: horizontalPadding + Double(index) * (itemWidth + itemGap),
                y: 0,
                width: itemWidth,
                height: itemHeight
            )
        }
    }
}

public struct TouchBarSessionSelectorItemFrame: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
