import Foundation

public struct ReadingProgressPresentation: Equatable {
    public var progressTitle: String

    public init(progressTitle: String) {
        self.progressTitle = progressTitle
    }
}

public enum ReadingProgressPresentationPolicy {
    public static func presentation(pageIndex: Int, pageCount: Int) -> ReadingProgressPresentation {
        guard pageCount > 0 else {
            return ReadingProgressPresentation(progressTitle: "Reading Progress: -")
        }

        let clampedIndex = min(max(pageIndex, 0), pageCount - 1)
        let currentPage = clampedIndex + 1
        let percent = Int((Double(currentPage) / Double(pageCount) * 100).rounded())
        return ReadingProgressPresentation(
            progressTitle: "Reading Progress: \(percent)% (\(currentPage)/\(pageCount))"
        )
    }
}
