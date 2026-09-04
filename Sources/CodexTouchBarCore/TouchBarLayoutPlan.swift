import Foundation

public enum TouchBarRegion: Equatable {
    case project
    case detailContent
    case flexibleSpace
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
        usesIdlePlayground: Bool = false,
        hasOpenSession: Bool = false,
        canDismissCompletion: Bool = false
    ) -> [TouchBarRegion] {
        var regions: [TouchBarRegion] = usesIdlePlayground
            ? [.detailContent]
            : [.project, .detailContent]
        if hasOpenSession {
            if usesIdlePlayground {
                regions.append(.flexibleSpace)
            }
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
