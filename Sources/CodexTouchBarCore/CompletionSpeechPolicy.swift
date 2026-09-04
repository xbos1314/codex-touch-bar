import Foundation

public enum CompletionSpeechRate: String, CaseIterable, Equatable, Sendable {
    case slow
    case normal
    case fast

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

    public var utteranceRate: Float {
        switch self {
        case .slow:
            return 0.42
        case .normal:
            return 0.50
        case .fast:
            return 0.58
        }
    }
}

public enum CompletionSpeechPitch: String, CaseIterable, Equatable, Sendable {
    case lower
    case normal
    case higher

    public var menuText: String {
        switch self {
        case .lower:
            return "Lower"
        case .normal:
            return "Normal"
        case .higher:
            return "Higher"
        }
    }

    public var multiplier: Float {
        switch self {
        case .lower:
            return 0.92
        case .normal:
            return 1.0
        case .higher:
            return 1.08
        }
    }
}

public struct CompletionSpeechVoiceOption: Equatable, Sendable {
    public var identifier: String
    public var name: String
    public var language: String
    public var qualityRank: Int

    public init(identifier: String, name: String, language: String, qualityRank: Int) {
        self.identifier = identifier
        self.name = name
        self.language = language
        self.qualityRank = qualityRank
    }
}

public enum CompletionSpeechVoicePolicy {
    public static func selectedVoiceIdentifier(
        from voices: [CompletionSpeechVoiceOption],
        preferredIdentifier: String?
    ) -> String? {
        if let preferredIdentifier,
           voices.contains(where: { $0.identifier == preferredIdentifier }) {
            return preferredIdentifier
        }

        if let chineseVoice = sortedVoiceOptions(voices).first(where: { isChineseLanguage($0.language) }) {
            return chineseVoice.identifier
        }

        return voices.first?.identifier
    }

    public static func sortedVoiceOptions(_ voices: [CompletionSpeechVoiceOption]) -> [CompletionSpeechVoiceOption] {
        voices.sorted { lhs, rhs in
            let lhsIsChinese = isChineseLanguage(lhs.language)
            let rhsIsChinese = isChineseLanguage(rhs.language)
            if lhsIsChinese != rhsIsChinese {
                return lhsIsChinese
            }
            let lhsFamilyRank = voiceFamilyRank(for: lhs)
            let rhsFamilyRank = voiceFamilyRank(for: rhs)
            if lhsFamilyRank != rhsFamilyRank {
                return lhsFamilyRank > rhsFamilyRank
            }
            let lhsPreferredRank = preferredChineseVoiceRank(for: lhs)
            let rhsPreferredRank = preferredChineseVoiceRank(for: rhs)
            if lhsPreferredRank != rhsPreferredRank {
                return lhsPreferredRank > rhsPreferredRank
            }
            if lhs.qualityRank != rhs.qualityRank {
                return lhs.qualityRank > rhs.qualityRank
            }
            if lhs.language != rhs.language {
                return lhs.language.localizedStandardCompare(rhs.language) == .orderedAscending
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func isChineseLanguage(_ language: String) -> Bool {
        language.lowercased().hasPrefix("zh")
    }

    private static func voiceFamilyRank(for voice: CompletionSpeechVoiceOption) -> Int {
        let identifier = voice.identifier.lowercased()
        if identifier.contains(".ttsbundle.siri_") {
            return 3
        }
        if identifier.contains(".eloquence.") || identifier.contains(".speech.synthesis.voice.") {
            return 1
        }
        return 2
    }

    private static func preferredChineseVoiceRank(for voice: CompletionSpeechVoiceOption) -> Int {
        guard isChineseLanguage(voice.language) else { return 0 }
        let normalizedName = voice.name
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalizedName {
        case "yushu":
            return 3
        case "limu":
            return 2
        case "tingting":
            return 1
        default:
            return 0
        }
    }
}

public struct CompletionSpeechState: Equatable, Sendable {
    public var sessionKey: String?
    public var turnKey: String?
    public var mood: TouchBarPetMood?
    public var moodsBySessionKey: [String: TouchBarPetMood]
    public var turnKeysBySessionKey: [String: String]
    public var spokenTurnKeysBySessionKey: [String: String]

    public init(
        sessionKey: String? = nil,
        turnKey: String? = nil,
        mood: TouchBarPetMood? = nil,
        moodsBySessionKey: [String: TouchBarPetMood] = [:],
        turnKeysBySessionKey: [String: String] = [:],
        spokenTurnKeysBySessionKey: [String: String] = [:]
    ) {
        self.sessionKey = sessionKey
        self.turnKey = turnKey
        self.mood = mood
        var knownMoods = moodsBySessionKey
        var knownTurnKeys = turnKeysBySessionKey
        if let sessionKey, let mood {
            knownMoods[sessionKey] = mood
        }
        if let sessionKey, let turnKey {
            knownTurnKeys[sessionKey] = turnKey
        }
        self.moodsBySessionKey = knownMoods
        self.turnKeysBySessionKey = knownTurnKeys
        self.spokenTurnKeysBySessionKey = spokenTurnKeysBySessionKey
    }
}

public struct CompletionSpeechDecision: Equatable, Sendable {
    public var shouldSpeak: Bool
    public var shouldStop: Bool
    public var textToSpeak: String?
    public var next: CompletionSpeechState

    public init(shouldSpeak: Bool, shouldStop: Bool, textToSpeak: String?, next: CompletionSpeechState) {
        self.shouldSpeak = shouldSpeak
        self.shouldStop = shouldStop
        self.textToSpeak = textToSpeak
        self.next = next
    }
}

public enum CompletionSpeechPolicy {
    public static let maximumSpokenCharacters = 500

    public static func evaluate(
        previous: CompletionSpeechState,
        isEnabled: Bool,
        sessionKey: String?,
        turnKey: String?,
        currentMood: TouchBarPetMood,
        assistantText: String?
    ) -> CompletionSpeechDecision {
        guard let sessionKey,
              !sessionKey.isEmpty else {
            return CompletionSpeechDecision(shouldSpeak: false, shouldStop: false, textToSpeak: nil, next: previous)
        }

        guard let turnKey, !turnKey.isEmpty else {
            let next = stateByRecording(
                previous: previous,
                sessionKey: sessionKey,
                turnKey: nil,
                mood: currentMood,
                spokenTurnKey: nil
            )
            return CompletionSpeechDecision(shouldSpeak: false, shouldStop: false, textToSpeak: nil, next: next)
        }

        let previousMood = previous.moodsBySessionKey[sessionKey]
        let previousTurnKey = previous.turnKeysBySessionKey[sessionKey]
        let spokenTurnKey = previous.spokenTurnKeysBySessionKey[sessionKey]
        let hasSeenSessionBefore = previousMood != nil || previousTurnKey != nil
        let turnChanged = previousTurnKey != nil && previousTurnKey != turnKey
        let shouldStop = turnChanged && currentMood != .completed
        let normalizedText = normalizedAssistantText(assistantText)
        let canSpeak = hasSeenSessionBefore
            && isEnabled
            && currentMood == .completed
            && spokenTurnKey != turnKey
            && normalizedText != nil

        let next = stateByRecording(
            previous: previous,
            sessionKey: sessionKey,
            turnKey: turnKey,
            mood: currentMood,
            spokenTurnKey: canSpeak ? turnKey : nil
        )
        return CompletionSpeechDecision(
            shouldSpeak: canSpeak,
            shouldStop: shouldStop,
            textToSpeak: canSpeak ? normalizedText : nil,
            next: next
        )
    }

    private static func normalizedAssistantText(_ text: String?) -> String? {
        guard let text else { return nil }
        let normalized = CodexDisplayTextFormatter.displayText(from: text)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(maximumSpokenCharacters))
    }

    private static func stateByRecording(
        previous: CompletionSpeechState,
        sessionKey: String,
        turnKey: String?,
        mood: TouchBarPetMood,
        spokenTurnKey: String?
    ) -> CompletionSpeechState {
        var knownMoods = previous.moodsBySessionKey
        var knownTurnKeys = previous.turnKeysBySessionKey
        var spokenTurnKeys = previous.spokenTurnKeysBySessionKey
        knownMoods[sessionKey] = mood
        if let turnKey {
            knownTurnKeys[sessionKey] = turnKey
        }
        if let spokenTurnKey {
            spokenTurnKeys[sessionKey] = spokenTurnKey
        }
        return CompletionSpeechState(
            sessionKey: sessionKey,
            turnKey: turnKey,
            mood: mood,
            moodsBySessionKey: knownMoods,
            turnKeysBySessionKey: knownTurnKeys,
            spokenTurnKeysBySessionKey: spokenTurnKeys
        )
    }
}
