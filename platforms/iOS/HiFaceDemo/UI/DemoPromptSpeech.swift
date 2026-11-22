import AVFoundation

/// Speaks each changed prompt in the language of the screen.
@MainActor
final class DemoPromptSpeech {
    private let language: String
    private lazy var voice = AVSpeechSynthesisVoice(language: language)
    private lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.usesApplicationAudioSession = false
        return synthesizer
    }()
    private var lastPrompt: String?

    init(language: String) {
        self.language = language
    }

    func speak(_ text: String?) {
        guard let text, !text.isEmpty, text != lastPrompt, let voice else { return }
        stop()
        lastPrompt = text
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    func stop() {
        guard lastPrompt != nil else { return }
        lastPrompt = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
