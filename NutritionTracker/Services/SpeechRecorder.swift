import AVFoundation
import Speech

/// Live dictation with Apple's speech recognizer. Recognition runs on the phone when the language model for the
/// current language is installed (it is for English on recent iPhones), so the audio never leaves the device.
@MainActor
final class SpeechRecorder: ObservableObject {
    /// Everything dictated or typed so far. Editable while not recording.
    @Published var text = ""
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Text from before this recording, so a second recording adds to the first instead of replacing it.
    private var prefix = ""

    func toggle() {
        if isRecording {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        errorMessage = nil
        guard await Self.requestSpeechPermission() else {
            errorMessage = "Allow speech recognition in Settings → Nutrition to dictate."
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Allow microphone access in Settings → Nutrition to dictate."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now. You can type instead."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            request.contextualStrings = ["oat milk", "cold brew", "Silk", "grams", "tablespoon", "teaspoon"]
            self.request = request

            Self.installTap(on: engine.inputNode, feeding: request)
            engine.prepare()
            try engine.start()

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            prefix = trimmed.isEmpty ? "" : trimmed + " "
            isRecording = true

            task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(for: self))
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
            finish()
        }
    }

    /// Stops listening; the recognizer still delivers its final transcription afterwards.
    func stop() {
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isRecording = false
    }

    func clear() {
        task?.cancel()
        finish()
        text = ""
        prefix = ""
    }

    private func handle(spoken: String?, isFinal: Bool, failed: Bool) {
        // After clear() the request is gone, so late results from a cancelled recording are dropped.
        guard request != nil else { return }
        if let spoken, isRecording || isFinal {
            text = prefix + spoken
        }
        if failed || isFinal {
            finish()
        }
    }

    // The audio tap and the recognizer call back on background threads, so their closures are made outside
    // the main actor and hop back to it explicitly.
    nonisolated private static func installTap(on input: AVAudioInputNode,
                                               feeding request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func resultHandler(for recorder: SpeechRecorder)
        -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak recorder] result, error in
            let spoken = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                recorder?.handle(spoken: spoken, isFinal: isFinal, failed: failed)
            }
        }
    }

    private func finish() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
