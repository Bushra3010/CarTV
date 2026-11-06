import AVFoundation
import Observation
import Speech

@MainActor @Observable
final class VoiceSearch {
    private(set) var transcript = ""
    private(set) var isListening = false
    private(set) var error: String?

    @ObservationIgnored private let recognizer = SFSpeechRecognizer()
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    func start() async {
        error = nil
        transcript = ""
        let status = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard status == .authorized else {
            error = "Turn on Speech Recognition for Backseat in Settings to search by voice."
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Turn on Microphone access for Backseat in Settings to search by voice."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            error = "Voice search isn't available right now."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            try Self.startEngine(engine, feeding: request)
            isListening = true
            task = Self.recognize(recognizer, request) { [weak self] text, failure, done in
                guard let self, self.isListening else { return }
                if let text { self.transcript = text }
                if done {
                    if self.transcript.isEmpty {
                        self.error = failure == nil
                            ? "Didn't catch that. Tap the mic and try again."
                            : "Voice search isn't working right now. Check that Dictation is turned on in Settings › General › Keyboard, then try again."
                    }
                    self.stop()
                }
            }
        } catch {
            self.error = "Couldn't start the microphone. \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
    }

    // Audio and speech callbacks arrive on background threads, so they are set up outside the main actor.
    private nonisolated static func startEngine(_ engine: AVAudioEngine, feeding request: SFSpeechAudioBufferRecognitionRequest) throws {
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private nonisolated static func recognize(_ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest,
                                              update: @escaping @MainActor (String?, String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let done = (result?.isFinal ?? false) || error != nil
            let message = error?.localizedDescription
            Task { @MainActor in update(text, message, done) }
        }
    }
}
