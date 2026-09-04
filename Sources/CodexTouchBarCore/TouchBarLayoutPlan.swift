import Foundation

public enum TouchBarRegion: Equatable {
    case project
    case detailContent
    case sessionSelector
    case openSession
    case idleSession
    case readingAutoPage
    case readingPreviousPage
    case readingNextPage
    case readingParagraphSelector
}

public enum TouchBarLayoutPlan {
    public static func visibleRegions(
        showingSessionSelector: Bool = false,
        hasOpenSession: Bool = false,
        canDismissCompletion: Bool = false
    ) -> [TouchBarRegion] {
        var regions: [TouchBarRegion] = [.project, .detailContent]
        if hasOpenSession {
            regions.append(.openSession)
        }
        if canDismissCompletion {
            regions.append(.idleSession)
        }
        return regions
    }

    public static func readingRegions() -> [TouchBarRegion] {
        [.readingAutoPage, .readingPreviousPage, .detailContent, .readingNextPage, .readingParagraphSelector]
    }
}
