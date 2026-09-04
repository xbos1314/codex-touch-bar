import Foundation

public enum TouchBarStatusIconTone: Equatable {
    case running
    case completed
    case failed
    case neutral
}

public struct TouchBarStatusIcon: Equatable {
    public var systemSymbolName: String
    public var accessibilityLabel: String
    public var fallbackText: String
    public var tone: TouchBarStatusIconTone
    public var rotationDegrees: Double

    public init(
        systemSymbolName: String,
        accessibilityLabel: String,
        fallbackText: String,
        tone: TouchBarStatusIconTone = .neutral,
        rotationDegrees: Double = 0
    ) {
        self.systemSymbolName = systemSymbolName
        self.accessibilityLabel = accessibilityLabel
        self.fallbackText = fallbackText
        self.tone = tone
        self.rotationDegrees = rotationDegrees
    }
}

public enum TouchBarStatusIconPolicy {
    public static func icon(
        for state: CodexDisplayState,
        now: Date = Date(),
        language: DisplayLanguage = .english
    ) -> TouchBarStatusIcon? {
        if state.status == .failed || state.latestActivity?.status == .failed {
            return statusIcon(symbol: "xmark.circle", english: "Failed", chinese: "失败", tone: .failed, language: language)
        }

        if state.isTaskComplete, state.status == .completed {
            return statusIcon(symbol: "checkmark.circle", english: "Completed", chinese: "已完成", tone: .completed, language: language)
        }

        if state.isTaskRunning || isRunning(state) {
            return runningFrame(now: now, language: language)
        }

        switch state.status {
        case .interrupted:
            return statusIcon(symbol: "stop.circle", english: "Stopped", chinese: "已停止", tone: .neutral, language: language)
        case .idle, .completed, .thinking, .runningTool, .readingFile, .editingFile, .waitingApproval, .failed:
            return nil
        }
    }

    private static func isRunning(_ state: CodexDisplayState) -> Bool {
        if state.latestActivity?.status == .running {
            return true
        }

        switch state.status {
        case .thinking, .runningTool, .readingFile, .editingFile, .waitingApproval:
            return true
        case .idle, .completed, .failed, .interrupted:
            return false
        }
    }

    private static func runningFrame(now: Date, language: DisplayLanguage) -> TouchBarStatusIcon {
        let frames = [
            "circle.bottomhalf.filled",
            "circle.lefthalf.filled",
            "circle.tophalf.filled",
            "circle.righthalf.filled"
        ]
        let index = Int(now.timeIntervalSince1970 * 2) % frames.count
        return statusIcon(symbol: frames[index], english: "Working", chinese: "执行中", tone: .running, language: language)
    }

    private static func statusIcon(
        symbol: String,
        english: String,
        chinese: String,
        tone: TouchBarStatusIconTone,
        language: DisplayLanguage
    ) -> TouchBarStatusIcon {
        let text = language == .english ? english : chinese
        return TouchBarStatusIcon(systemSymbolName: symbol, accessibilityLabel: text, fallbackText: text, tone: tone)
    }
}

public struct TouchBarProjectStatusFrame: Equatable {
    public var width: Double
    public var height: Double
    public var buttonWidth: Double
    public var iconX: Double
    public var iconY: Double
    public var iconSize: Double

    public init(width: Double, height: Double, buttonWidth: Double, iconX: Double, iconY: Double, iconSize: Double) {
        self.width = width
        self.height = height
        self.buttonWidth = buttonWidth
        self.iconX = iconX
        self.iconY = iconY
        self.iconSize = iconSize
    }
}

public enum TouchBarProjectStatusLayout {
    public static func frame(height: Double = TouchBarLayoutMetrics.detailViewportHeight) -> TouchBarProjectStatusFrame {
        return TouchBarProjectStatusFrame(
            width: 42,
            height: height,
            buttonWidth: 0,
            iconX: 0,
            iconY: 0,
            iconSize: 42
        )
    }
}
