public struct CompletionSoundState: Equatable, Sendable {
    public var sessionKey: String?
    public var mood: TouchBarPetMood?
    public var moodsBySessionKey: [String: TouchBarPetMood]
    public var turnKeysBySessionKey: [String: String]
    public var playedTurnKeysBySessionKey: [String: String]

    public init(
        sessionKey: String? = nil,
        mood: TouchBarPetMood? = nil,
        moodsBySessionKey: [String: TouchBarPetMood] = [:],
        turnKeysBySessionKey: [String: String] = [:],
        playedTurnKeysBySessionKey: [String: String] = [:]
    ) {
        self.sessionKey = sessionKey
        self.mood = mood
        var knownMoods = moodsBySessionKey
        if let sessionKey, let mood {
            knownMoods[sessionKey] = mood
        }
        self.moodsBySessionKey = knownMoods
        self.turnKeysBySessionKey = turnKeysBySessionKey
        self.playedTurnKeysBySessionKey = playedTurnKeysBySessionKey
    }
}

public struct CompletionSoundDecision: Equatable, Sendable {
    public var shouldPlay: Bool
    public var next: CompletionSoundState

    public init(shouldPlay: Bool, next: CompletionSoundState) {
        self.shouldPlay = shouldPlay
        self.next = next
    }
}

public enum CompletionSoundPolicy {
    public static func evaluate(
        previous: CompletionSoundState,
        sessionKey: String?,
        turnKey: String?,
        currentMood: TouchBarPetMood
    ) -> CompletionSoundDecision {
        guard let sessionKey, !sessionKey.isEmpty else {
            return CompletionSoundDecision(shouldPlay: false, next: previous)
        }

        guard let turnKey, !turnKey.isEmpty else {
            var knownMoods = previous.moodsBySessionKey
            knownMoods[sessionKey] = currentMood
            let next = CompletionSoundState(
                sessionKey: sessionKey,
                mood: currentMood,
                moodsBySessionKey: knownMoods,
                turnKeysBySessionKey: previous.turnKeysBySessionKey,
                playedTurnKeysBySessionKey: previous.playedTurnKeysBySessionKey
            )
            return CompletionSoundDecision(shouldPlay: false, next: next)
        }

        let previousMood = previous.moodsBySessionKey[sessionKey]
        let previousTurnKey = previous.turnKeysBySessionKey[sessionKey]
        let playedTurnKey = previous.playedTurnKeysBySessionKey[sessionKey]
        var knownMoods = previous.moodsBySessionKey
        var knownTurnKeys = previous.turnKeysBySessionKey
        var playedTurnKeys = previous.playedTurnKeysBySessionKey
        knownMoods[sessionKey] = currentMood
        knownTurnKeys[sessionKey] = turnKey

        let hasSeenSessionBefore = previousMood != nil || previousTurnKey != nil
        let isNewCompletionForTurn = currentMood == .completed && playedTurnKey != turnKey
        let hasTransitionedIntoCompletion = previousMood != .completed || previousTurnKey != turnKey
        let shouldPlay = hasSeenSessionBefore && isNewCompletionForTurn && hasTransitionedIntoCompletion
        if shouldPlay {
            playedTurnKeys[sessionKey] = turnKey
        }

        let next = CompletionSoundState(
            sessionKey: sessionKey,
            mood: currentMood,
            moodsBySessionKey: knownMoods,
            turnKeysBySessionKey: knownTurnKeys,
            playedTurnKeysBySessionKey: playedTurnKeys
        )
        return CompletionSoundDecision(shouldPlay: shouldPlay, next: next)
    }
}
