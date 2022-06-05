//
//  RecordedMediaPlayback.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import AVFoundation

/// RecordedMediaPlayback plays media recorded from the microphone to a local file.
class RecordedMediaPlayback: NSObject {
    static let shared = RecordedMediaPlayback()

    private var audioPlayer = AVAudioPlayer()

    /// Playback the latest record.
    public func play(record: URL) {
        if audioPlayer.isPlaying {
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: record)
            audioPlayer.enableRate = false
            audioPlayer.rate = 1.0
            audioPlayer.delegate = self
            audioPlayer.numberOfLoops = 0
            audioPlayer.play()
        } catch {
            Cache.log.error("Unable to start playback: %@", error.localizedDescription)
        }
    }

    func stop() {
        audioPlayer.stop()
    }

    func restartPlayer() {
        audioPlayer.stop()
        audioPlayer.currentTime = 0
        audioPlayer.play()
    }
}

extension RecordedMediaPlayback: AVAudioPlayerDelegate{
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    }
}
