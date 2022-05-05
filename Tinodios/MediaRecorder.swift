//
//  MediaRecorder.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import AVFoundation

protocol MediaRecorderDelegate: AnyObject {
    func didStartRecording()
    func didFinishRecording(url: URL?, duration: TimeInterval)
    func didUpdateRecording(amplitude: Float, atTime: TimeInterval)
    func didFailRecording(_ error: Error)
}

enum MediaRecorderError: Error {
    case permissionDenyedError
    case unknownPermissionError
}

/// MediaRecorder currenly support audio recording only.
class MediaRecorder: NSObject {
    private static let kTimerPrecision: TimeInterval = 0.03
    private static let kSampleRate = 16000

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

    public var delegate: MediaRecorderDelegate?
    public var timerPrecision = MediaRecorder.kTimerPrecision
    public var saveRecordingToPath = FileManager.SearchPathDirectory.cachesDirectory
    public var duration: Int?

    /// URL of the latest record.
    public var recordFileURL: URL? {
        guard let name = self.latestRecordName else { return nil }
        let path = FileManager.default.urls(for: self.saveRecordingToPath, in: .userDomainMask)[0]
        return path.appendingPathComponent("\(name).m4a")
    }

    public func start() {
        switch self.session.recordPermission {
        case .undetermined:
            self.session.requestRecordPermission({response in
                DispatchQueue.main.async {
                    if response {
                        self.startRecording()
                    } else {
                        // Permission denyed.
                        self.delegate?.didFailRecording(MediaRecorderError.permissionDenyedError)
                    }
                }
            })
            break
        case .granted:
            self.startRecording()
        case .denied:
            self.delegate?.didFailRecording(MediaRecorderError.unknownPermissionError)
        @unknown default:
            // Ignored: do nothing.
            break
        }
    }

    private func startRecording() {
        self.latestRecordName = NSUUID().uuidString
        do {
            try self.session.setCategory(AVAudioSession.Category.playAndRecord, options: .defaultToSpeaker)
            self.audioRecorder = try AVAudioRecorder(url: self.recordFileURL!, settings: settings)
            self.audioRecorder.delegate = self
            self.audioRecorder.isMeteringEnabled = true
            self.audioRecorder.prepareToRecord()
        } catch {
            self.delegate?.didFailRecording(error)
            print("Error setting up: %@", error.localizedDescription)
            return
        }

        if !audioRecorder.isRecording {
            do {
                try self.session.setActive(true)
                self.updateTimer = Timer.scheduledTimer(timeInterval: self.timerPrecision, target: self, selector: #selector(self.recordUpdate), userInfo: nil, repeats: true)
                self.duration = 0
                self.audioRecorder.record()
                self.delegate?.didStartRecording()
            } catch {
                self.delegate?.didFailRecording(error)
                print("Error recording: %@", error.localizedDescription)
            }
        }
    }

    public func stop() {
        guard let recordURL = self.recordFileURL else { return }

        let duration = self.audioRecorder.currentTime
        self.duration = Int(duration * 1000)
        self.audioRecorder.stop()
        self.delegate?.didFinishRecording(url: recordURL, duration: duration)
        do {
            try self.session.setActive(false)
        } catch {
            print("Failed to stop recording: %@", error.localizedDescription)
        }
    }

    public func pause() {
        guard self.recordFileURL != nil else { return }
        self.audioRecorder.pause()
    }

    func delete() {
        guard let recordURL = self.recordFileURL else { return }

        let manager = FileManager.default
        if manager.fileExists(atPath: recordURL.path) {
            do {
                try manager.removeItem(at: recordURL)
                self.latestRecordName = nil
            } catch {
                print("Failed to delete recording: %@", error.localizedDescription)
            }
        } else {
            // The recording does not exist.
            self.latestRecordName = nil
            self.duration = nil
        }
    }

    @objc func recordUpdate() {
        if self.audioRecorder.isRecording {
            self.audioRecorder.updateMeters()
            self.delegate?.didUpdateRecording(amplitude: self.audioRecorder.averagePower(forChannel: 0), atTime: self.audioRecorder.currentTime)
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
    }
}
