import AVFoundation
import Observation
import Speech

/// Talking to Lovely (owner, Nov 16, 2026): the mic in the card's field turns what he says into words on this iPhone
/// (Apple's on-device speech; `scripts/privacy_guard.py` fails without requiresOnDeviceRecognition). It stops after a
/// short pause or a tap. Nothing happens on voice alone: the words become a question or a date he still confirms.
@MainActor
@Observable
final class SpeechDictation {
    enum State: Equatable {
        case idle
        case listening
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var text = ""
    /// Called once with the final words (possibly empty).
    var onFinish: ((String) -> Void)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var silence: Task<Void, Never>?

    var isListening: Bool { state == .listening }

    func start() async {
        guard state != .listening else { return }
        text = ""
        state = .listening
        let speechAllowed = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speechAllowed else { return fail("Turn on Speech Recognition for Lovely in Settings to talk to it.") }
        guard await AVAudioApplication.requestRecordPermission() else {
            return fail("Turn on the microphone for Lovely in Settings to talk to it.")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            return fail("This iPhone can't turn speech into words on the phone. Type it instead.")
        }
        guard state == .listening else { return }   // cancelled while asking
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            Self.tap(engine.inputNode, into: request)
            engine.prepare()
            try engine.start()
            task = Self.recognize(recognizer, request) { [weak self] words, final, failed in
                Task { @MainActor in self?.heard(words, final: final, failed: failed) }
            }
            armSilence(seconds: 6)
        } catch {
            fail("The microphone didn't start. Type it instead.")
        }
    }

    /// Done talking (the stop button).
    func stop() { finish() }

    /// Closed without using the words.
    func cancel() {
        teardown()
        state = .idle
    }

    private func heard(_ words: String?, final: Bool, failed: Bool) {
        guard state == .listening else { return }
        if let words, !words.isEmpty { text = words; armSilence(seconds: 1.6) }
        if final || failed { finish() }
    }

    private func armSilence(seconds: Double) {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func finish() {
        guard state == .listening else { return }
        teardown()
        state = .idle
        onFinish?(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func fail(_ message: String) {
        teardown()
        state = .failed(message)
    }

    private func teardown() {
        silence?.cancel(); silence = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Formed outside the main actor: the audio and speech callbacks run on their own threads.
    nonisolated private static func tap(_ input: AVAudioInputNode, into request: SFSpeechAudioBufferRecognitionRequest) {
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognize(_ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest,
                                              _ update: @escaping @Sendable (String?, Bool, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            update(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }
}
