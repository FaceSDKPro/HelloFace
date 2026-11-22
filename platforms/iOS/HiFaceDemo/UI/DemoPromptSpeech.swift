import AVFoundation

/// Speaks each changed prompt in the language of the screen.
@MainActor
final class DemoPromptSpeech: NSObject, AVSpeechSynthesizerDelegate {
    private static var finishingPrompt: DemoPromptSpeech?
    private let language: String
    private lazy var voice = AVSpeechSynthesisVoice(language: language)
    private lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.usesApplicationAudioSession = false
        synthesizer.delegate = self
        return synthesizer
    }()
    private var lastPrompt: String?
    private var currentUtterance: AVSpeechUtterance?
    private var started = false

    init(language: String) {
        self.language = language
        super.init()
        Self.finishingPrompt?.stop()
    }

    func speak(_ text: String?) {
        guard let text, !text.isEmpty, text != lastPrompt, let voice else { return }
        stop()
        lastPrompt = text
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }

    /// Keep only the current audio during normal navigation.
    func finish() {
        guard Self.finishingPrompt !== self else { return }
        guard started, synthesizer.isSpeaking, !synthesizer.isPaused else {
            stop()
            return
        }
        Self.finishingPrompt?.stop()
        Self.finishingPrompt = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, Self.finishingPrompt === self else { return }
            self.stop()
        }
    }

    func stop() {
        if Self.finishingPrompt === self { Self.finishingPrompt = nil }
        guard lastPrompt != nil else { return }
        lastPrompt = nil
        currentUtterance = nil
        started = false
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, let currentUtterance, ObjectIdentifier(currentUtterance) == id else { return }
            started = true
        }
    }
}
