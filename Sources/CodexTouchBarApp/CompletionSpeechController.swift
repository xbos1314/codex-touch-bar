import AVFoundation
import CodexTouchBarCore

@MainActor
final class CompletionSpeechController {
    private var state = CompletionSpeechState()
    private let synthesizer = AVSpeechSynthesizer()

    func apply(
        state displayState: CodexDisplayState,
        isEnabled: Bool,
        voiceIdentifier: String?,
        voiceOptions: [CompletionSpeechVoiceOption],
        rate: CompletionSpeechRate,
        pitch: CompletionSpeechPitch
    ) {
        let decision = CompletionSpeechPolicy.evaluate(
            previous: state,
            isEnabled: isEnabled,
            sessionKey: displayState.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
            turnKey: turnKey(for: displayState),
            currentMood: TouchBarPetPolicy.mood(for: displayState, isReading: false),
            assistantText: displayState.latestAssistantText
        )
        state = decision.next

        if decision.shouldStop {
            stop()
        }
        guard let text = decision.textToSpeak else { return }

        speak(
            text,
            voiceIdentifier: CompletionSpeechVoicePolicy.selectedVoiceIdentifier(
                from: voiceOptions,
                preferredIdentifier: voiceIdentifier
            ),
            rate: rate,
            pitch: pitch
        )
    }

    func reset() {
        state = CompletionSpeechState()
        stop()
    }

    func stop() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speak(
        _ text: String,
        voiceIdentifier: String?,
        rate: CompletionSpeechRate,
        pitch: CompletionSpeechPitch
    ) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        }
        utterance.rate = rate.utteranceRate
        utterance.pitchMultiplier = pitch.multiplier
        synthesizer.speak(utterance)
    }

    private func turnKey(for state: CodexDisplayState) -> String? {
        if let timestamp = state.latestUserTimestamp?.trimmingCharacters(in: .whitespacesAndNewlines),
           !timestamp.isEmpty {
            return timestamp
        }

        if let text = state.latestUserText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        return nil
    }
}
