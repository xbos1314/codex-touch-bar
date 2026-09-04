import Foundation

public struct TouchBarAutoScrollStep: Equatable {
    public var offset: Double
    public var wrappedToStart: Bool
    public var reachedEnd: Bool

    public init(offset: Double, wrappedToStart: Bool, reachedEnd: Bool = false) {
        self.offset = offset
        self.wrappedToStart = wrappedToStart
        self.reachedEnd = reachedEnd
    }
}

public enum TouchBarAutoScrollPolicy {
    public static let pixelsPerSecond: Double = 56
    public static let userInteractionPauseSeconds: Double = 4
    public static let restartPauseSeconds: Double = 1.5

    public static func nextStep(
        currentOffset: Double,
        contentWidth: Double,
        documentWidth: Double,
        viewportWidth: Double,
        elapsedSeconds: Double,
        now: Double,
        pauseUntil: Double?
    ) -> TouchBarAutoScrollStep {
        guard contentWidth > viewportWidth else {
            return TouchBarAutoScrollStep(offset: 0, wrappedToStart: false)
        }
        if let pauseUntil, now < pauseUntil {
            return TouchBarAutoScrollStep(offset: currentOffset, wrappedToStart: false)
        }

        let maxOffset = max(0, documentWidth - viewportWidth)
        if currentOffset >= maxOffset {
            return TouchBarAutoScrollStep(offset: 0, wrappedToStart: true)
        }

        let next = currentOffset + pixelsPerSecond * elapsedSeconds
        if next >= maxOffset {
            return TouchBarAutoScrollStep(offset: maxOffset, wrappedToStart: false, reachedEnd: true)
        }
        return TouchBarAutoScrollStep(offset: next, wrappedToStart: false)
    }

    public static func nextOffset(
        currentOffset: Double,
        contentWidth: Double,
        documentWidth: Double,
        viewportWidth: Double,
        elapsedSeconds: Double,
        now: Double,
        pauseUntil: Double?
    ) -> Double {
        nextStep(
            currentOffset: currentOffset,
            contentWidth: contentWidth,
            documentWidth: documentWidth,
            viewportWidth: viewportWidth,
            elapsedSeconds: elapsedSeconds,
            now: now,
            pauseUntil: pauseUntil
        ).offset
    }

    public static func pauseUntil(afterUserInteractionAt now: Double) -> Double {
        now + userInteractionPauseSeconds
    }

    public static func pauseUntil(afterWrapAt now: Double) -> Double {
        now + restartPauseSeconds
    }

    public static func pauseUntil(afterContentResetAt now: Double) -> Double {
        now + restartPauseSeconds
    }
}
