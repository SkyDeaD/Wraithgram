import Foundation
import AVFoundation
import Speech
import NaturalLanguage
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import WGCore

enum WGSubtitlesError: Error {
    case noAudio
    case noPermission
    case notRecognized
    case cancelled
}

/// Speech → timed lines for a gallery video.
///
/// Engine, as decided for voice transcription (OWNER_DECISIONS 2026-10-21): with Premium, a message
/// Telegram can transcribe (a round video) uses Telegram's server transcription of that same message;
/// everything else uses Apple Speech — on the device when the language model is there, otherwise
/// Apple's server. Nothing is uploaded and no message is sent anywhere.
///
/// Audio is read in 30-second windows straight from the file and fed to the recognizer as it is
/// read: at most one window (≈ 2 MB) is in memory, never the whole track.
final class WGSubtitlesEngine {
    static let shared = WGSubtitlesEngine()

    private struct CacheEntry {
        let key: String
        let track: WGSubtitleTrack
    }

    private let lock = NSLock()
    /// Most recent first; at most `cacheLimit` tracks.
    private var cache: [CacheEntry] = []
    private let cacheLimit = 8

    private init() {
    }

    func track(context: AccountContext, message: Message, file: TelegramMediaFile) -> Signal<WGSubtitleTrack, WGSubtitlesError> {
        let targetLanguage = WGCallsMediaSettings.subtitlesTranslate.value ? WGSubtitlesEngine.targetLanguage(context: context) : nil
        let key = "\(file.fileId.namespace):\(file.fileId.id):\(targetLanguage ?? "-")"
        if let cached = self.cached(key) {
            return .single(cached)
        }
        let duration = file.duration ?? 0.0
        let recognized: Signal<WGSubtitleTrack, WGSubtitlesError>
        if context.isPremium && (file.isInstantVideo || file.isVoice) {
            recognized = WGSubtitlesEngine.telegramTrack(context: context, messageId: message.id, duration: duration)
            |> `catch` { _ -> Signal<WGSubtitleTrack, WGSubtitlesError> in
                return WGSubtitlesEngine.appleTrack(context: context, message: message, file: file, duration: duration)
            }
        } else {
            recognized = WGSubtitlesEngine.appleTrack(context: context, message: message, file: file, duration: duration)
        }
        return recognized
        |> mapToSignal { track -> Signal<WGSubtitleTrack, WGSubtitlesError> in
            guard let targetLanguage = targetLanguage else {
                return .single(track)
            }
            return WGSubtitlesEngine.translated(track, context: context, language: targetLanguage)
        }
        |> afterNext { [weak self] track in
            self?.store(key: key, track: track)
        }
    }

    private func cached(_ key: String) -> WGSubtitleTrack? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        guard let index = self.cache.firstIndex(where: { $0.key == key }) else {
            return nil
        }
        let entry = self.cache.remove(at: index)
        self.cache.insert(entry, at: 0)
        return entry.track
    }

    private func store(key: String, track: WGSubtitleTrack) {
        self.lock.lock()
        self.cache.removeAll(where: { $0.key == key })
        self.cache.insert(CacheEntry(key: key, track: track), at: 0)
        if self.cache.count > self.cacheLimit {
            self.cache.removeLast(self.cache.count - self.cacheLimit)
        }
        self.lock.unlock()
    }

    static func targetLanguage(context: AccountContext) -> String {
        let setting = WGCallsMediaSettings.subtitlesLanguage.value
        if !setting.isEmpty {
            return setting
        }
        let code = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        return WGSubtitlesEngine.normalizedLanguage(code)
    }

    static func normalizedLanguage(_ code: String) -> String {
        let lowered = code.lowercased()
        if let range = lowered.range(of: "-") {
            return String(lowered[..<range.lowerBound])
        }
        if let range = lowered.range(of: "_") {
            return String(lowered[..<range.lowerBound])
        }
        return lowered
    }

    // MARK: Telegram

    private static func telegramTrack(context: AccountContext, messageId: MessageId, duration: Double) -> Signal<WGSubtitleTrack, WGSubtitlesError> {
        let transcribe = context.engine.messages.transcribeAudio(messageId: messageId)
        |> castError(WGSubtitlesError.self)
        |> mapToSignal { result -> Signal<WGSubtitleTrack, WGSubtitlesError> in
            if case .error = result {
                return .fail(.notRecognized)
            }
            // The text may still be streaming in; wait for the final one.
            return context.engine.data.subscribe(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
            |> castError(WGSubtitlesError.self)
            |> mapToSignal { message -> Signal<WGSubtitleTrack, WGSubtitlesError> in
                guard let message = message else {
                    return .fail(.notRecognized)
                }
                for attribute in message.attributes {
                    if let attribute = attribute as? AudioTranscriptionMessageAttribute {
                        if attribute.error != nil {
                            return .fail(.notRecognized)
                        }
                        if attribute.isPending {
                            return .complete()
                        }
                        let words = WGSubtitleCueBuilder.estimatedWords(text: attribute.text, duration: duration)
                        let cues = WGSubtitleCueBuilder.cues(words: words, mediaDuration: duration)
                        if cues.isEmpty {
                            return .fail(.notRecognized)
                        }
                        return .single(WGSubtitleTrack(cues: cues, isTimingEstimated: true))
                    }
                }
                return .complete()
            }
            |> take(1)
        }
        return transcribe
        |> timeout(120.0, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.notRecognized))
    }

    // MARK: Apple Speech

    private static func appleTrack(context: AccountContext, message: Message, file: TelegramMediaFile, duration: Double) -> Signal<WGSubtitleTrack, WGSubtitlesError> {
        let localePreference = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        return WGSubtitlesEngine.authorized()
        |> mapToSignal { _ -> Signal<String, WGSubtitlesError> in
            return WGSubtitlesEngine.localPath(context: context, message: message, file: file)
        }
        |> mapToSignal { path -> Signal<WGSubtitleTrack, WGSubtitlesError> in
            return Signal { subscriber in
                let recognizer = WGSpeechStreamRecognizer(url: URL(fileURLWithPath: path), localePreference: localePreference)
                recognizer.start(completion: { result in
                    switch result {
                    case let .success(words):
                        let cues = WGSubtitleCueBuilder.cues(words: words, mediaDuration: duration > 0.0 ? duration : nil)
                        if cues.isEmpty {
                            subscriber.putError(.notRecognized)
                        } else {
                            subscriber.putNext(WGSubtitleTrack(cues: cues, isTimingEstimated: false))
                            subscriber.putCompletion()
                        }
                    case let .failure(error):
                        subscriber.putError(error)
                    }
                })
                return ActionDisposable {
                    recognizer.cancel()
                }
            }
        }
    }

    private static func authorized() -> Signal<Void, WGSubtitlesError> {
        return Signal { subscriber in
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized:
                subscriber.putNext(Void())
                subscriber.putCompletion()
            case .notDetermined:
                SFSpeechRecognizer.requestAuthorization { status in
                    if status == .authorized {
                        subscriber.putNext(Void())
                        subscriber.putCompletion()
                    } else {
                        subscriber.putError(.noPermission)
                    }
                }
            default:
                subscriber.putError(.noPermission)
            }
            return EmptyDisposable
        }
    }

    /// The video file on disk (with an extension AVFoundation can open), downloading it if needed.
    private static func localPath(context: AccountContext, message: Message, file: TelegramMediaFile) -> Signal<String, WGSubtitlesError> {
        let mediaBox = context.account.postbox.mediaBox
        let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(message.id.peerId), userContentType: .video, reference: FileMediaReference.message(message: MessageReference(message), media: file).resourceReference(file.resource))
        |> `catch` { _ -> Signal<FetchResourceSourceType, NoError> in
            return .complete()
        }
        let data = mediaBox.resourceData(file.resource, pathExtension: "mp4", option: .complete(waitUntilFetchStatus: false))
        |> filter { $0.complete }
        |> take(1)
        |> map { $0.path }
        // The download runs only while someone waits for the complete file.
        return Signal { subscriber in
            let fetchDisposable = fetch.start()
            let dataDisposable = data.start(next: { path in
                subscriber.putNext(path)
                subscriber.putCompletion()
            })
            return ActionDisposable {
                fetchDisposable.dispose()
                dataDisposable.dispose()
            }
        }
    }

    // MARK: Translation

    /// Lines go through the app's translation service (Telegram, or what the user picked in
    /// «Перевод»), in batches.
    private static func translated(_ track: WGSubtitleTrack, context: AccountContext, language: String) -> Signal<WGSubtitleTrack, WGSubtitlesError> {
        let sample = track.cues.prefix(20).map { $0.text }.joined(separator: " ")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        if let detected = recognizer.dominantLanguage?.rawValue, WGSubtitlesEngine.normalizedLanguage(detected) == language {
            return .single(track)
        }
        let batchSize = 30
        var batches: [Signal<[String], NoError>] = []
        var start = 0
        while start < track.cues.count {
            let end = min(track.cues.count, start + batchSize)
            let lines = track.cues[start ..< end].map { $0.text }
            batches.append(context.engine.messages.translate(texts: lines.map { ($0, []) }, toLang: language)
            |> map { result -> [String] in
                if result.count == lines.count {
                    return result.map { $0.0 }
                }
                return lines
            }
            |> `catch` { _ -> Signal<[String], NoError> in
                return .single(lines)
            })
            start = end
        }
        return combineLatest(batches)
        |> map { parts -> WGSubtitleTrack in
            var updated = track
            var index = 0
            for part in parts {
                for line in part where index < updated.cues.count {
                    updated.cues[index].text = line
                    index += 1
                }
            }
            return updated
        }
        |> castError(WGSubtitlesError.self)
    }
}

/// Feeds an audio track to `SFSpeechRecognizer` window by window.
private final class WGSpeechStreamRecognizer {
    private static let sampleRate: Double = 16000.0
    private static let windowSeconds: Double = 30.0

    private let url: URL
    private let localePreference: String
    private let queue = Queue(name: "org.wraithgram.subtitles")

    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var words: [WGSubtitleWord] = []
    private var windowStart: Double = 0.0
    private var isCancelled = false
    private var completion: ((Result<[WGSubtitleWord], WGSubtitlesError>) -> Void)?

    init(url: URL, localePreference: String) {
        self.url = url
        self.localePreference = localePreference
    }

    func start(completion: @escaping (Result<[WGSubtitleWord], WGSubtitlesError>) -> Void) {
        self.completion = completion
        let asset = AVURLAsset(url: self.url)
        asset.loadTracks(withMediaType: .audio, completionHandler: { [weak self] tracks, _ in
            guard let strongSelf = self else {
                return
            }
            strongSelf.queue.async {
                strongSelf.begin(asset: asset, track: tracks?.first)
            }
        })
    }

    func cancel() {
        self.queue.async {
            self.isCancelled = true
            self.task?.cancel()
            self.task = nil
            self.reader?.cancelReading()
            self.completion = nil
        }
    }

    private func finish(_ result: Result<[WGSubtitleWord], WGSubtitlesError>) {
        self.reader?.cancelReading()
        self.reader = nil
        self.task = nil
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }

    private func begin(asset: AVURLAsset, track: AVAssetTrack?) {
        if self.isCancelled {
            return
        }
        guard let track = track, let reader = try? AVAssetReader(asset: asset) else {
            self.finish(.failure(.noAudio))
            return
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: WGSpeechStreamRecognizer.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            self.finish(.failure(.noAudio))
            return
        }
        reader.add(output)
        guard reader.startReading() else {
            self.finish(.failure(.noAudio))
            return
        }
        guard let recognizer = WGSpeechStreamRecognizer.makeRecognizer(preference: self.localePreference) else {
            self.finish(.failure(.notRecognized))
            return
        }
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        recognizer.queue = operationQueue
        self.reader = reader
        self.output = output
        self.recognizer = recognizer
        self.runWindow()
    }

    private static func makeRecognizer(preference: String) -> SFSpeechRecognizer? {
        let wanted = WGSubtitlesEngine.normalizedLanguage(preference)
        let supported = SFSpeechRecognizer.supportedLocales()
        var candidates: [Locale] = []
        if let exact = supported.first(where: { WGSubtitlesEngine.normalizedLanguage($0.identifier) == wanted }) {
            candidates.append(exact)
        }
        candidates.append(Locale.current)
        candidates.append(Locale(identifier: "en-US"))
        for locale in candidates {
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable {
                return recognizer
            }
        }
        return nil
    }

    private func runWindow() {
        if self.isCancelled {
            return
        }
        guard let reader = self.reader, let output = self.output, let recognizer = self.recognizer else {
            return
        }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: WGSpeechStreamRecognizer.sampleRate, channels: 1, interleaved: false) else {
            self.finish(.failure(.noAudio))
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        // On the device when the language is downloaded; otherwise Apple's server (owner decision).
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        request.taskHint = .dictation

        let windowStart = self.windowStart
        let windowFrames = WGSpeechStreamRecognizer.sampleRate * WGSpeechStreamRecognizer.windowSeconds
        var appendedFrames: Double = 0.0
        var reachedEnd = false

        self.task = recognizer.recognitionTask(with: request, resultHandler: { [weak self] result, error in
            guard let strongSelf = self else {
                return
            }
            let isFinal = result?.isFinal ?? false
            if !isFinal && error == nil {
                return
            }
            var windowWords: [WGSubtitleWord] = []
            if let result = result {
                for segment in result.bestTranscription.segments {
                    windowWords.append(WGSubtitleWord(text: segment.substring, start: windowStart + segment.timestamp, duration: segment.duration))
                }
            }
            strongSelf.queue.async {
                if strongSelf.isCancelled {
                    return
                }
                strongSelf.words.append(contentsOf: windowWords)
                if reachedEnd {
                    strongSelf.finish(strongSelf.words.isEmpty ? .failure(.notRecognized) : .success(strongSelf.words))
                } else {
                    strongSelf.windowStart = windowStart + appendedFrames / WGSpeechStreamRecognizer.sampleRate
                    strongSelf.runWindow()
                }
            }
        })

        while appendedFrames < windowFrames {
            guard reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() else {
                reachedEnd = true
                break
            }
            let frames = CMSampleBufferGetNumSamples(sampleBuffer)
            guard frames > 0, let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)), let channel = buffer.floatChannelData?[0] else {
                continue
            }
            buffer.frameLength = AVAudioFrameCount(frames)
            let status = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: frames * MemoryLayout<Float>.size, destination: channel)
            if status != kCMBlockBufferNoErr {
                continue
            }
            request.append(buffer)
            appendedFrames += Double(frames)
        }
        if appendedFrames == 0.0 {
            // Nothing left to recognize (the previous window ended exactly at the end).
            self.task?.cancel()
            self.task = nil
            self.finish(self.words.isEmpty ? .failure(.notRecognized) : .success(self.words))
            return
        }
        request.endAudio()
    }
}
