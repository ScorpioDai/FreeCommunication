import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

struct CapturedChunk: Hashable, Sendable {
    var url: URL
    var channel: SegmentChannel
    var startedAt: Date
}

struct CapturedPCMChunk: Hashable, Sendable {
    var data: Data
    var channel: SegmentChannel
    var startedAt: Date
}

final class LiveAudioCapture {
    private let microphone = MicrophoneChunkCapture()
    private let systemAudio = SystemAudioChunkCapture()
    private let chunksLock = NSLock()
    private var activeMode: CommunicationMode?
    private var callback: ((CapturedChunk) -> Void)?
    private var pcmCallback: ((CapturedPCMChunk) -> Void)?
    private var directory: URL?
    private var chunkSeconds: TimeInterval = 6
    private var callVoiceProcessingEnabled = false
    private var recordedChunks: [CapturedChunk] = []

    func start(
        mode: CommunicationMode,
        microphoneEnabled: Bool,
        chunkSeconds: TimeInterval,
        directory: URL,
        callVoiceProcessingEnabled: Bool,
        onChunk: ((CapturedChunk) -> Void)?,
        onPCM: ((CapturedPCMChunk) -> Void)? = nil
    ) async throws {
        if activeMode != nil {
            _ = await stop()
        }
        self.activeMode = mode
        self.callback = onChunk
        self.pcmCallback = onPCM
        self.directory = directory
        self.chunkSeconds = chunkSeconds
        self.callVoiceProcessingEnabled = callVoiceProcessingEnabled
        resetRecordedChunks()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if mode.capturesSystemAudio {
            try await systemAudio.start(chunkSeconds: chunkSeconds, directory: directory, onChunk: { [weak self] chunk in
                self?.remember(chunk)
                self?.callback?(chunk)
            }, onPCM: { [weak self] packet in
                self?.pcmCallback?(packet)
            })
        }

        if microphoneEnabled && mode.capturesMicrophoneByDefault {
            try await microphone.start(chunkSeconds: chunkSeconds, directory: directory, voiceProcessingEnabled: mode == .call && callVoiceProcessingEnabled, onChunk: { [weak self] chunk in
                self?.remember(chunk)
                self?.callback?(chunk)
            }, onPCM: { [weak self] packet in
                self?.pcmCallback?(packet)
            })
        }
    }

    func setMicrophoneEnabled(_ enabled: Bool) async throws {
        guard let mode = activeMode, mode.capturesMicrophoneByDefault, let directory else { return }
        if enabled {
            if !microphone.isRunning {
                try await microphone.start(chunkSeconds: chunkSeconds, directory: directory, voiceProcessingEnabled: mode == .call && callVoiceProcessingEnabled, onChunk: { [weak self] chunk in
                    self?.remember(chunk)
                    self?.callback?(chunk)
                }, onPCM: { [weak self] packet in
                    self?.pcmCallback?(packet)
                })
            }
        } else {
            _ = microphone.stop()
        }
    }

    func stop() async -> [CapturedChunk] {
        let mic = microphone.stop()
        let system = await systemAudio.stop()
        let chunks = finishRecordedChunks(extra: mic + system)
        activeMode = nil
        callback = nil
        pcmCallback = nil
        directory = nil
        callVoiceProcessingEnabled = false
        return chunks
    }

    private func remember(_ chunk: CapturedChunk) {
        chunksLock.lock()
        recordedChunks.append(chunk)
        chunksLock.unlock()
    }

    private func resetRecordedChunks() {
        chunksLock.lock()
        recordedChunks.removeAll()
        chunksLock.unlock()
    }

    private func finishRecordedChunks(extra: [CapturedChunk]) -> [CapturedChunk] {
        chunksLock.lock()
        var chunks = recordedChunks + extra
        recordedChunks.removeAll()
        chunksLock.unlock()

        var seen = Set<URL>()
        chunks = chunks.filter { chunk in
            if seen.contains(chunk.url) {
                return false
            }
            seen.insert(chunk.url)
            return true
        }
        return chunks.sorted { $0.startedAt < $1.startedAt }
    }
}

final class PCMChunkAccumulator {
    private let lock = NSLock()
    private var data = Data()
    private var startedAt = Date()
    private let thresholdBytes: Int

    init(seconds: TimeInterval = 0.5, sampleRate: Double = 16_000) {
        thresholdBytes = max(8_000, Int(seconds * sampleRate) * MemoryLayout<Float>.size)
    }

    func append(_ chunk: Data, capturedAt: Date, channel: SegmentChannel) -> CapturedPCMChunk? {
        guard !chunk.isEmpty else { return nil }
        lock.lock()
        if data.isEmpty {
            startedAt = capturedAt
        }
        data.append(chunk)
        let packet: CapturedPCMChunk?
        if data.count >= thresholdBytes {
            packet = CapturedPCMChunk(data: data, channel: channel, startedAt: startedAt)
            data.removeAll(keepingCapacity: true)
            startedAt = Date()
        } else {
            packet = nil
        }
        lock.unlock()
        return packet
    }

    func finish(channel: SegmentChannel) -> CapturedPCMChunk? {
        lock.lock()
        defer { lock.unlock() }
        guard !data.isEmpty else { return nil }
        let packet = CapturedPCMChunk(data: data, channel: channel, startedAt: startedAt)
        data.removeAll(keepingCapacity: true)
        startedAt = Date()
        return packet
    }
}

final class PCMFloat32Converter {
    private let lock = NSLock()
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!
    private var converter: AVAudioConverter?
    private var sourceSignature = ""

    func data(from buffer: AVAudioPCMBuffer) -> Data? {
        guard buffer.frameLength > 0 else { return nil }
        lock.lock()
        defer { lock.unlock() }

        let sourceFormat = buffer.format
        let signature = "\(sourceFormat.sampleRate)-\(sourceFormat.channelCount)-\(sourceFormat.commonFormat.rawValue)-\(sourceFormat.isInterleaved)"
        if converter == nil || sourceSignature != signature {
            converter = AVAudioConverter(from: sourceFormat, to: outputFormat)
            sourceSignature = signature
        }
        guard let converter else { return nil }

        let ratio = outputFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(max(1, Double(buffer.frameLength) * ratio + 512))
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        guard conversionError == nil, let channel = output.floatChannelData?[0], output.frameLength > 0 else {
            return nil
        }
        return Data(bytes: channel, count: Int(output.frameLength) * MemoryLayout<Float>.size)
    }
}

enum SampleBufferPCM {
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        else {
            return nil
        }
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0, let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            return nil
        }
        output.frameLength = AVAudioFrameCount(sampleCount)

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: format.channelCount, mDataByteSize: 0, mData: nil)
        )
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let sourceBuffer = audioBufferList.mBuffers
        let destinationList = output.mutableAudioBufferList.pointee
        let destinationBuffer = destinationList.mBuffers
        guard let source = sourceBuffer.mData, let destination = destinationBuffer.mData else { return nil }
        memcpy(destination, source, min(Int(sourceBuffer.mDataByteSize), Int(destinationBuffer.mDataByteSize)))
        return output
    }
}

final class MicrophoneChunkCapture {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private let pcmAccumulator = PCMChunkAccumulator()
    private let pcmConverter = PCMFloat32Converter()
    private var currentFile: AVAudioFile?
    private var currentURL: URL?
    private var currentStartedAt = Date()
    private var timer: DispatchSourceTimer?
    private var onChunk: ((CapturedChunk) -> Void)?
    private var onPCM: ((CapturedPCMChunk) -> Void)?
    private(set) var isRunning = false

    func start(
        chunkSeconds: TimeInterval,
        directory: URL,
        voiceProcessingEnabled: Bool = false,
        onChunk: ((CapturedChunk) -> Void)?,
        onPCM: ((CapturedPCMChunk) -> Void)? = nil
    ) async throws {
        guard !isRunning else { return }
        self.onChunk = onChunk
        self.onPCM = onPCM

        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            throw NSError(domain: "FreeCommunication", code: 20, userInfo: [NSLocalizedDescriptionKey: "麦克风权限未开启。"])
        }

        let input = engine.inputNode
        do {
            try input.setVoiceProcessingEnabled(voiceProcessingEnabled)
            if voiceProcessingEnabled {
                NSLog("FreeCommunication microphone voice processing enabled.")
            }
        } catch {
            NSLog("FreeCommunication microphone voice processing unavailable: %@", error.localizedDescription)
        }
        let format = input.outputFormat(forBus: 0)
        try openNewFile(directory: directory, format: format)

        input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            lock.lock()
            let file = currentFile
            lock.unlock()
            try? file?.write(from: buffer)
            if let data = pcmConverter.data(from: buffer),
               let packet = pcmAccumulator.append(data, capturedAt: Date(), channel: .microphone) {
                onPCM?(packet)
            }
        }

        try engine.start()
        isRunning = true

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + chunkSeconds, repeating: chunkSeconds)
        timer.setEventHandler { [weak self] in
            self?.rotate(directory: directory, format: format)
        }
        timer.resume()
        self.timer = timer
    }

    func stop() -> [CapturedChunk] {
        guard isRunning else { return [] }
        timer?.cancel()
        timer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        isRunning = false
        if let packet = pcmAccumulator.finish(channel: .microphone) {
            onPCM?(packet)
        }
        onPCM = nil
        return finishCurrent()
    }

    private func rotate(directory: URL, format: AVAudioFormat) {
        let chunks = finishCurrent()
        for chunk in chunks {
            DispatchQueue.main.async { [onChunk] in onChunk?(chunk) }
        }
        try? openNewFile(directory: directory, format: format)
    }

    private func openNewFile(directory: URL, format: AVAudioFormat) throws {
        let url = directory
            .appendingPathComponent("mic-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        lock.lock()
        currentFile = file
        currentURL = url
        currentStartedAt = Date()
        lock.unlock()
    }

    private func finishCurrent() -> [CapturedChunk] {
        lock.lock()
        let url = currentURL
        let startedAt = currentStartedAt
        currentFile = nil
        currentURL = nil
        lock.unlock()

        guard let url, FileManager.default.fileExists(atPath: url.path) else { return [] }
        return [CapturedChunk(url: url, channel: .microphone, startedAt: startedAt)]
    }
}

final class SystemAudioChunkCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "FreeCommunication.system-audio")
    private let pcmAccumulator = PCMChunkAccumulator()
    private let pcmConverter = PCMFloat32Converter()
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var currentURL: URL?
    private var currentStartedAt = Date()
    private var timer: DispatchSourceTimer?
    private var onChunk: ((CapturedChunk) -> Void)?
    private var onPCM: ((CapturedPCMChunk) -> Void)?
    private var directory: URL?
    private var isRunning = false
    private var sampleBufferCount = 0
    private var appendedBufferCount = 0
    private var skippedBufferCount = 0
    private var loggedFormat = false

    func start(
        chunkSeconds: TimeInterval,
        directory: URL,
        onChunk: ((CapturedChunk) -> Void)?,
        onPCM: ((CapturedPCMChunk) -> Void)? = nil
    ) async throws {
        guard !isRunning else { return }
        self.onChunk = onChunk
        self.onPCM = onPCM
        self.directory = directory

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw NSError(domain: "FreeCommunication", code: 30, userInfo: [NSLocalizedDescriptionKey: "没有可捕捉的显示器。"])
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 1
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 16_000
        configuration.channelCount = 1

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        self.isRunning = true

        queue.async { [weak self] in
            self?.openNewWriter()
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + chunkSeconds, repeating: chunkSeconds)
        timer.setEventHandler { [weak self] in
            self?.rotateWriter()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() async -> [CapturedChunk] {
        guard isRunning else { return [] }
        timer?.cancel()
        timer = nil
        isRunning = false
        if let stream {
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(self, type: .audio)
        }
        stream = nil
        if let packet = pcmAccumulator.finish(channel: .system) {
            onPCM?(packet)
        }
        onChunk = nil
        onPCM = nil
        directory = nil
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.finishWriter(callback: false) { chunk in
                    continuation.resume(returning: chunk.map { [$0] } ?? [])
                }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        sampleBufferCount += 1
        logFormatIfNeeded(sampleBuffer)
        if let buffer = SampleBufferPCM.pcmBuffer(from: sampleBuffer),
           let data = pcmConverter.data(from: buffer),
           let packet = pcmAccumulator.append(data, capturedAt: Date(), channel: .system) {
            onPCM?(packet)
        }
        if writer == nil {
            openNewWriter()
        }
        guard let writer, let writerInput else {
            skippedBufferCount += 1
            return
        }
        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        if writer.status == .writing, writerInput.isReadyForMoreMediaData {
            if writerInput.append(sampleBuffer) {
                appendedBufferCount += 1
            } else {
                skippedBufferCount += 1
                if writer.status == .failed {
                    NSLog("FreeCommunication system audio writer append failed: %@", writer.error?.localizedDescription ?? "unknown error")
                }
            }
        } else if writer.status == .failed {
            skippedBufferCount += 1
            NSLog("FreeCommunication system audio writer failed: %@", writer.error?.localizedDescription ?? "unknown error")
        } else {
            skippedBufferCount += 1
        }
    }

    private func rotateWriter() {
        finishWriter(callback: true) { [weak self] chunk in
            if let chunk {
                DispatchQueue.main.async { self?.onChunk?(chunk) }
            }
            self?.openNewWriter()
        }
    }

    private func openNewWriter() {
        guard let directory else { return }
        let url = directory
            .appendingPathComponent("system-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .caf)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                NSLog("FreeCommunication system writer cannot add PCM audio input.")
                return
            }
            writer.add(input)
            self.writer = writer
            self.writerInput = input
            self.currentURL = url
            self.currentStartedAt = Date()
            self.sampleBufferCount = 0
            self.appendedBufferCount = 0
            self.skippedBufferCount = 0
            self.loggedFormat = false
        } catch {
            NSLog("FreeCommunication system writer error: %@", error.localizedDescription)
        }
    }

    private func finishWriter(callback: Bool, completion: @escaping (CapturedChunk?) -> Void) {
        guard let writer, let input = writerInput, let url = currentURL else {
            completion(nil)
            return
        }
        let startedAt = currentStartedAt
        let sampleCount = sampleBufferCount
        let appendedCount = appendedBufferCount
        let skippedCount = skippedBufferCount
        self.writer = nil
        self.writerInput = nil
        self.currentURL = nil

        if writer.status == .unknown {
            writer.cancelWriting()
            NSLog("FreeCommunication system audio chunk had no writable samples. samples=%d appended=%d skipped=%d", sampleCount, appendedCount, skippedCount)
            completion(nil)
            return
        }

        input.markAsFinished()
        writer.finishWriting {
            guard writer.status == .completed, FileManager.default.fileExists(atPath: url.path) else {
                NSLog("FreeCommunication system audio finish failed: %@ samples=%d appended=%d skipped=%d", writer.error?.localizedDescription ?? "unknown error", sampleCount, appendedCount, skippedCount)
                completion(nil)
                return
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            NSLog("FreeCommunication system audio chunk ready: %@ bytes=%lld samples=%d appended=%d skipped=%d", url.lastPathComponent, size, sampleCount, appendedCount, skippedCount)
            guard size > 512, appendedCount > 0 else {
                completion(nil)
                return
            }
            completion(CapturedChunk(url: url, channel: .system, startedAt: startedAt))
        }
    }

    private func logFormatIfNeeded(_ sampleBuffer: CMSampleBuffer) {
        guard !loggedFormat else { return }
        loggedFormat = true
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            NSLog("FreeCommunication system audio sample format unavailable.")
            return
        }
        let description = streamDescription.pointee
        NSLog(
            "FreeCommunication system audio sample format: %@",
            "rate=\(Int(description.mSampleRate)) channels=\(description.mChannelsPerFrame) format=\(description.mFormatID) frames=\(CMSampleBufferGetNumSamples(sampleBuffer))"
        )
    }
}
