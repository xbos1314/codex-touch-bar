import Foundation

public enum ReadingAutoPageSpeed: String, CaseIterable, Equatable, Sendable {
    case slow
    case normal
    case fast

    public var intervalSeconds: TimeInterval {
        switch self {
        case .slow:
            return 5.0
        case .normal:
            return 3.0
        case .fast:
            return 1.5
        }
    }

    public var menuText: String {
        switch self {
        case .slow:
            return "Slow"
        case .normal:
            return "Normal"
        case .fast:
            return "Fast"
        }
    }
}

public enum ReadingAutoPagePolicy {
    public static func canAdvanceAutomatically(currentIndex: Int, pageCount: Int) -> Bool {
        pageCount > 1 && currentIndex >= 0 && currentIndex < pageCount - 1
    }
}
