//
//  MediaRecorder.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import AVFoundation

protocol MediaRecorderDelegate: AnyObject {
    func didStartRecording(recorder: MediaRecorder)
    func didFinishRecording(recorder: MediaRecorder, url: URL?, duration: TimeInterval)
    func didUpdateRecording(recorder: MediaRecorder, amplitude: Float, atTime: TimeInterval)
    func didFailRecording(recorder: MediaRecorder, _ error: Error)
}

enum MediaRecorderError: LocalizedError, CustomStringConvertible {
    case permissionDenyed
    case unknownPermission
    case permissionRequested
    case cancelledByUser

    public var description: String {
        get {
            switch self {
            case .permissionDenyed:
                return "Permission denyed"
            case .unknownPermission:
                return "Unknown permission"
            case .permissionRequested:
                return "Permission requested"
            case .cancelledByUser:
                return "Cancelled by user"
            }
        }
    }
}

/// MediaRecorder currenly support audio recording only.
class MediaRecorder: NSObject {
    private static let kTimerPrecision: TimeInterval = 0.03
    private static let kSampleRate = 16000
    private static let kPreviewBars = 96

    private var session = AVAudioSession.sharedInstance()
    private var audioRecorder: AVAudioRecorder!

    private var settings = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: MediaRecorder.kSampleRate,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
    ]

    private var updateTimer: Timer!
    private var latestRecordName: String?
    private var audioSampler = AudioSampler()

    public weak var delegate: MediaRecorderDelegate?
    public var timerPrecision = MediaRecorder.kTimerPrecision
    public var saveRecordingToPath = FileManager.SearchPathDirectory.cachesDirectory
    public var duration: Int?
    public var maxDuration: Int?

    /// URL of the latest record.
    public var recordFileURL: URL? {
        guard let name = self.latestRecordName else { return nil }
        let path = FileManager.default.urls(for: self.saveRecordingToPath, in: .userDomainMask)[0]
        return path.appendingPathComponent("\(name).m4a")
    }

    public var isRecording: Bool {
        return self.audioRecorder.isRecording
    }

    public func start() {
        let recordTimeLimit: TimeInterval? = self.maxDuration != nil ? TimeInterval(self.maxDuration!) / 1000 : nil

        switch self.session.recordPermission {
        case .undetermined:
            self.delegate?.didFailRecording(recorder: self, MediaRecorderError.permissionRequested)
            self.session.requestRecordPermission({response in
                DispatchQueue.main.async {
                    if response {
                        self.startRecording(forDuration: recordTimeLimit)
                    } else {
                        // Permission denyed.
                        self.delegate?.didFailRecording(recorder: self, MediaRecorderError.permissionDenyed)
                    }
                }
            })
            break
        case .granted:
            self.startRecording(forDuration: recordTimeLimit)
        case .denied:
            self.delegate?.didFailRecording(recorder: self, MediaRecorderError.unknownPermission)
        @unknown default:
            // Ignored: do nothing.
            break
        }
    }

    private func startRecording(forDuration: TimeInterval?) {
        self.latestRecordName = NSUUID().uuidString
        do {
            try self.session.setCategory(AVAudioSession.Category.playAndRecord, options: .defaultToSpeaker)
            self.audioRecorder = try AVAudioRecorder(url: self.recordFileURL!, settings: settings)
            self.audioRecorder.delegate = self
            self.audioRecorder.isMeteringEnabled = true
            self.audioRecorder.prepareToRecord()
        } catch {
            self.delegate?.didFailRecording(recorder: self, error)
            Cache.log.error("Failed to setup recorder: %@", error.localizedDescription)
            return
        }

        if !audioRecorder.isRecording {
            do {
                try self.session.setActive(true)
                self.updateTimer = Timer.scheduledTimer(timeInterval: self.timerPrecision, target: self, selector: #selector(self.recordUpdate), userInfo: nil, repeats: true)
                self.duration = 0
                if let maxDuration = forDuration {
                    self.audioRecorder.record(forDuration: maxDuration)
                } else {
                    self.audioRecorder.record()
                }
                self.delegate?.didStartRecording(recorder: self)
            } catch {
                self.delegate?.didFailRecording(recorder: self, error)
                Cache.log.error("Failed to start recording: %@", error.localizedDescription)
            }
        }
    }

    public func stop(discard: Bool = false) {
        guard let recordURL = self.recordFileURL else { return }

        let duration = self.audioRecorder.currentTime
        self.audioRecorder.stop()
        if discard {
            self.delete()
            self.delegate?.didFailRecording(recorder: self, MediaRecorderError.cancelledByUser)
        } else {
            self.duration = Int(duration * 1000)
            self.delegate?.didFinishRecording(recorder: self, url: recordURL, duration: duration)
        }
        do {
            try self.session.setActive(false)
        } catch {
            Cache.log.error("Failed to stop recording: %@", error.localizedDescription)
        }
    }

    public func pause() {
        guard self.recordFileURL != nil else { return }
        self.audioRecorder.pause()
    }

    public func delete() {
        guard let recordURL = self.recordFileURL else { return }

        let manager = FileManager.default
        if manager.fileExists(atPath: recordURL.path) {
            do {
                try manager.removeItem(at: recordURL)
                self.latestRecordName = nil
                self.duration = nil
                self.audioSampler = AudioSampler()
            } catch {
                Cache.log.error("Failed to delete recording: %@", error.localizedDescription)
            }
        } else {
            // The recording does not exist.
            self.latestRecordName = nil
            self.duration = nil
            self.audioSampler = AudioSampler()
        }
    }

    public var preview: Data {
        return audioSampler.obtain(dstCount: MediaRecorder.kPreviewBars)
    }

    @objc func recordUpdate() {
        if self.audioRecorder.isRecording {
            self.audioRecorder.updateMeters()
            let amplitude = pow(10, 0.1 * self.audioRecorder.averagePower(forChannel: 0))
            self.audioSampler.put(amplitude)
            self.delegate?.didUpdateRecording(recorder: self, amplitude: amplitude, atTime: self.audioRecorder.currentTime)
            self.duration = Int(self.audioRecorder.currentTime * 1000)
        } else {
            self.updateTimer.invalidate()
        }
    }
}


extension MediaRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        updateTimer.invalidate()
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Cache.log.error("Error while recording: %@", error?.localizedDescription ?? "nil")
        updateTimer.invalidate()
    }
}

// Class for generating audio preview from a stream of amplitudes of unknown length.
private class AudioSampler {
    private static let kVisualizationBars = 128

    private var samples: [Float]
    private var scratchBuff: [Float]
    // The index of a bucket being filled.
    private var bucketIndex: Int
    // Number of samples per bucket in mScratchBuff.
    private var aggregateCount: Int
    // Number of samples added the the current bucket.
    private var samplesPerBucket: Int

    init() {
        samples = [Float](repeating: 0, count: AudioSampler.kVisualizationBars * 2)
        scratchBuff = [Float](repeating: 0, count: AudioSampler.kVisualizationBars)
        bucketIndex = 0
        samplesPerBucket = 0
        aggregateCount = 1
    }

    public func put(_ val: Float) {
        // Fill out the main buffer first.
        if aggregateCount == 1 {
            if bucketIndex < samples.count {
                samples[bucketIndex] = val
                bucketIndex += 1
                return
            }
            compact()
        }

        // Check if the current bucket is full.
        if samplesPerBucket == aggregateCount {
            // Normalize the bucket.
            scratchBuff[bucketIndex] = scratchBuff[bucketIndex] / Float(samplesPerBucket)
            bucketIndex += 1
            samplesPerBucket = 0
        }

        // Check if scratch buffer is full.
        if bucketIndex == scratchBuff.count {
            compact()
        }
        scratchBuff[bucketIndex] += Float(val)
        samplesPerBucket += 1
    }

    // Get the count of available samples in the main buffer + scratch buffer.
    private var length: Int {
        if aggregateCount == 1 {
            // Only the main buffer is available.
            return bucketIndex
        }
        // Completely filled main buffer + partially filled scratch buffer.
        return samples.count + bucketIndex + 1
    }

    // Get bucket content at the given index from the main + scratch buffer.
    private func getAt(_ index: Int) -> Float {
        var index = index
        // Index into the main buffer.
        if index < samples.count {
            return samples[index]
        }
        // Index into scratch buffer.
        index -= samples.count
        if index < bucketIndex {
            return scratchBuff[index]
        }
        // Last partially filled bucket in the scratch buffer.
        return scratchBuff[index] / Float(samplesPerBucket)
    }

    public func obtain(dstCount: Int) -> Data {
        // We can only return as many as we have.
        var dst = [Float](repeating: 0, count: dstCount)
        let srcCount = self.length
        // Resampling factor. Couple be lower or higher than 1.
        let factor: Float = Float(srcCount) / Float(dstCount)
        var maxAmp: Float = -1
        // src = 100, dst = 200, factor = 0.5
        // src = 200, dst = 100, factor = 2.0
        for i in 0..<dstCount {
            let lo = Int(Float(i) * factor) // low bound
            let hi = Int(Float(i + 1) * factor) // high bound
            if (hi == lo) {
                dst[i] = getAt(lo)
            } else {
                var amp: Float = 0
                for j in lo..<hi {
                    amp += getAt(j)
                }
                dst[i] = max(0, amp / Float(hi - lo))
            }
            maxAmp = max(dst[i], maxAmp)
        }

        var result = [UInt8](repeating: 0, count: dst.count)
        if maxAmp > 0 {
            for i in 0..<dst.count {
                result[i] = UInt8(100 * dst[i] / maxAmp)
            }
        }

        return Data(result)
    }

    // Downscale the amplitudes 2x.
    private func compact() {
        let len = AudioSampler.kVisualizationBars / 2
        // Donwsample the main buffer: two consecutive samples make one new sample.
        for i in 0..<len {
            samples[i] = (samples[i * 2] + samples[i * 2 + 1]) * 0.5
        }
        // Copy scratch buffer to the upper half the the main buffer.
        for i in 0..<len {
            samples[len + i] = scratchBuff[i]
        }
        // Clear the scratch buffer.
        scratchBuff = scratchBuff.map{ _ in return 0 }
        // Double the number of samples per bucket.
        aggregateCount *= 2
        // Reset scratch counters.
        bucketIndex = 0
        samplesPerBucket = 0
    }
}
