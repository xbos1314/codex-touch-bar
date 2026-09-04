import Foundation

public struct TouchBarContentFrame: Equatable {
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

public enum TouchBarLayoutMetrics {
    public static let detailViewportHeight: Double = 30
    public static let detailMinimumWidth: Double = 560
    public static let detailTrailingPadding: Double = 24

    public static func centeredContentFrame(
        containerWidth: Double,
        containerHeight: Double,
        contentWidth: Double,
        contentHeight: Double
    ) -> TouchBarContentFrame {
        let y = max(0, (containerHeight - contentHeight) / 2)
        return TouchBarContentFrame(x: 0, y: y, width: containerWidth, height: contentHeight)
    }
}
