//
//  MessageViewController+VLCMediaPlayerDelegate.swift
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import AVFAudio
import Foundation
import MobileCoreServices
import MobileVLCKit
import UIKit

extension MessageCell: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ notification: Notification) {
        guard let player = notification.object as? VLCMediaPlayer else { return }

        switch player.state {
        case .playing, .paused, .opening, .buffering, .esAdded:
            break
        case .error:
            Cache.log.error("MessageCell - media playback failed")
            fallthrough
        case .stopped, .ended:
            if mediaEntityKey != nil {
                self.delegate?.didEndMediaPlayback(in: self, audioPlayer: player)
                mediaEntityKey = nil
            }
        default:
            break
        }
    }

    func stopAudio() {
        if audioPlayer?.isPlaying ?? false {
            audioPlayer!.stop()
        }
    }

    fileprivate func initAudioPlayer() {
        if audioPlayer == nil {
            audioPlayer = VLCMediaPlayer()
            audioPlayer!.delegate = self
            speakerphone(on: true)
        }
    }

    fileprivate func initMedia(ref: String?, data: Data?, duration: Int, key: Int) {
        if (self.mediaEntityKey ?? -1) == key {
            // Already properly initialized with the same data.
            return
        }
        if let ref = ref, let url = Cache.tinode.toAbsoluteURL(origUrl: ref) {
            audioPlayer!.media = VLCMedia(url: Cache.tinode.addAuthQueryParams(url))
        } else if let data = data {
            audioPlayer!.media = VLCMedia(stream: InputStream(data: data))
        } else {
            Cache.log.info("MessageCell - unable to play audio: no data")
            return
        }

        if audioPlayer!.media!.length.intValue <= 0 && duration > 0 {
            audioPlayer!.media!.length = VLCTime(int: Int32(duration))
        }

        self.mediaEntityKey = key
    }

    func toggleAudioPlay(url: String?, data: Data?, duration: Int, key: Int) {
        initAudioPlayer()

        if audioPlayer!.isPlaying {
            audioPlayer!.pause()
            self.delegate?.didPauseMedia(in: self, audioPlayer: self.audioPlayer!)
            return
        }

        initMedia(ref: url, data: data, duration: duration, key: key)
        audioPlayer!.play()
        self.delegate?.didActivateMedia(in: self, audioPlayer: self.audioPlayer!)
    }

    func audioSeekTo(_ seekTo: Float, url: String?, data: Data?, duration: Int, key: Int) {
        initAudioPlayer()

        initMedia(ref: url, data: data, duration: duration, key: key)
        var doPause = false
        if !audioPlayer!.isPlaying {
            audioPlayer!.play()
            doPause = true
        }
        audioPlayer!.position = seekTo
        if doPause {
            // There is a bug in VLCPLayer: pause() is ignored if called too soon after play().
            // https://code.videolan.org/videolan/VLCKit/-/issues/610
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                // Async: audioPlayer may have been freed already.
                self.audioPlayer?.pause()
            }
        }
        self.delegate?.didSeekMedia(in: self, audioPlayer: self.audioPlayer!, pos: seekTo)
    }

    private func speakerphone(on: Bool) {
        let session = AVAudioSession.sharedInstance()
        if on {
            do {
                try session.setCategory(AVAudioSession.Category.playAndRecord)
                try session.setActive(true)
                try session.overrideOutputAudioPort(AVAudioSession.PortOverride.speaker)
            } catch let error as NSError {
                Cache.log.error("Failed to enable speakerphone: %@", error.localizedDescription)
            }
        } else {
            do {
                try session.setActive(false)
            } catch let error as NSError {
                Cache.log.error("Failed to disable audio session: %@", error.localizedDescription)
            }
        }
    }
}
