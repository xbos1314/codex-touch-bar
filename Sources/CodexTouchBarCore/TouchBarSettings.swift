import Foundation

public enum DisplayLanguage: String, CaseIterable, Equatable, Sendable {
    case english
    case simplifiedChinese
}

public enum TouchBarDetailDisplayMode: String, Equatable {
    case scrolling
    case paging

    public var menuText: String {
        switch self {
        case .scrolling:
            return "Scrolling"
        case .paging:
            return "Paging"
        }
    }
}

public struct TouchBarSettings {
    private static let displayLanguageKey = "display.language"
    private static let detailDisplayModeKey = "touchBar.detailDisplayMode"
    private static let completionSpeechEnabledKey = "completion.speechEnabled"
    private static let completionSpeechVoiceIdentifierKey = "completion.speechVoiceIdentifier"
    private static let completionSpeechRateKey = "completion.speechRate"
    private static let completionSpeechPitchKey = "completion.speechPitch"
    private static let readingAutoPageSpeedKey = "reading.autoPageSpeed"
    private static let lastReadingFilePathKey = "reading.lastFilePath"
    private static let readingPageIndexesKey = "reading.pageIndexes"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var displayLanguage: DisplayLanguage {
        get {
            guard let rawValue = defaults.string(forKey: Self.displayLanguageKey),
                  let language = DisplayLanguage(rawValue: rawValue) else {
                return .english
            }
            return language
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.displayLanguageKey)
        }
    }

    public var detailDisplayMode: TouchBarDetailDisplayMode {
        get {
            guard let rawValue = defaults.string(forKey: Self.detailDisplayModeKey),
                  let mode = TouchBarDetailDisplayMode(rawValue: rawValue) else {
                return .scrolling
            }
            return mode
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.detailDisplayModeKey)
        }
    }

    public var readingAutoPageSpeed: ReadingAutoPageSpeed {
        get {
            guard let rawValue = defaults.string(forKey: Self.readingAutoPageSpeedKey),
                  let speed = ReadingAutoPageSpeed(rawValue: rawValue) else {
                return .normal
            }
            return speed
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.readingAutoPageSpeedKey)
        }
    }

    public var completionSpeechEnabled: Bool {
        get {
            guard defaults.object(forKey: Self.completionSpeechEnabledKey) != nil else {
                return true
            }
            return defaults.bool(forKey: Self.completionSpeechEnabledKey)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Self.completionSpeechEnabledKey)
        }
    }

    public var completionSpeechVoiceIdentifier: String? {
        get {
            guard let identifier = defaults.string(forKey: Self.completionSpeechVoiceIdentifierKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !identifier.isEmpty else {
                return nil
            }
            return identifier
        }
        nonmutating set {
            guard let identifier = newValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !identifier.isEmpty else {
                defaults.removeObject(forKey: Self.completionSpeechVoiceIdentifierKey)
                return
            }
            defaults.set(identifier, forKey: Self.completionSpeechVoiceIdentifierKey)
        }
    }

    public var completionSpeechRate: CompletionSpeechRate {
        get {
            guard let rawValue = defaults.string(forKey: Self.completionSpeechRateKey),
                  let rate = CompletionSpeechRate(rawValue: rawValue) else {
                return .normal
            }
            return rate
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.completionSpeechRateKey)
        }
    }

    public var completionSpeechPitch: CompletionSpeechPitch {
        get {
            guard let rawValue = defaults.string(forKey: Self.completionSpeechPitchKey),
                  let pitch = CompletionSpeechPitch(rawValue: rawValue) else {
                return .normal
            }
            return pitch
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.completionSpeechPitchKey)
        }
    }

    public var lastReadingFilePath: String? {
        get {
            guard let path = defaults.string(forKey: Self.lastReadingFilePathKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else {
                return nil
            }
            return path
        }
        nonmutating set {
            guard let path = newValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else {
                defaults.removeObject(forKey: Self.lastReadingFilePathKey)
                return
            }
            defaults.set(path, forKey: Self.lastReadingFilePathKey)
        }
    }

    public func readingPageIndex(forFilePath filePath: String) -> Int {
        readingPageIndexes()[normalizedFilePath(filePath)] ?? 0
    }

    public func setReadingPageIndex(_ pageIndex: Int, forFilePath filePath: String) {
        let path = normalizedFilePath(filePath)
        guard !path.isEmpty else { return }
        var indexes = readingPageIndexes()
        indexes[path] = max(0, pageIndex)
        defaults.set(indexes, forKey: Self.readingPageIndexesKey)
    }

    private func readingPageIndexes() -> [String: Int] {
        defaults.dictionary(forKey: Self.readingPageIndexesKey) as? [String: Int] ?? [:]
    }

    private func normalizedFilePath(_ filePath: String) -> String {
        filePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
