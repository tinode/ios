//
//  MessageViewController+VLCMediaPlayerDelegate.swift
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import MobileCoreServices
import MobileVLCKit
import UIKit

extension MessageCell: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ notification: Notification) {
        guard let player = notification.object as? VLCMediaPlayer else { return }

        switch player.state {
        case .playing, .opening, .paused, .buffering, .esAdded:
            break
        case .error:
            self.delegate?.didEndMediaPlayback(in: self, audioPlayer: player)
            Cache.log.error("MessageCell - media playback failed")
            fallthrough
        case .stopped:
            print("stopped")
            // Must reopen: VLCMedia closes the InputStrem.
            self.mediaStream = nil
            self.audioPlayer?.media = nil
        case .ended:
            self.delegate?.didEndMediaPlayback(in: self, audioPlayer: player)
        default:
            break
        }
    }

    func mediaPlayerTimeChanged(_ notification: Notification) {
        // guard let player = notification.object as? VLCMediaPlayer else { return }
    }

    func stopAudio() {
        if let player = audioPlayer {
            if player.isPlaying {
                player.stop()
            }
        }
    }

    fileprivate func initAudioPlayer() {
        if audioPlayer == nil {
            audioPlayer = VLCMediaPlayer()
            audioPlayer!.delegate = self
        }
    }

    fileprivate func initMedia(url: URL?, data: Data?, duration: Int, key: Int) {
        if (self.mediaEntityKey ?? -1) == key && self.mediaStream != nil {
            // Already properly initialized with the same data.
            return
        }

        if let url = url {
            audioPlayer!.media = VLCMedia(url: url)
        } else if let data = data {
            // VLCMedia keep only weak reference to InputStream, must retain a strong reference.
            self.mediaStream = InputStream(data: data)
            audioPlayer!.media = VLCMedia(stream: self.mediaStream!)
        } else {
            Cache.log.error("MessageCell - unable to play audio: no data")
            return
        }
        if audioPlayer!.media.length.intValue <= 0 && duration > 0 {
            audioPlayer!.media.length = VLCTime(int: Int32(duration))
        }

        self.mediaEntityKey = key
    }

    func toggleAudioPlay(url: URL?, data: Data?, duration: Int, key: Int) {
        initAudioPlayer()

        if audioPlayer!.isPlaying {
            audioPlayer!.pause()
            self.delegate?.didPauseMedia(in: self, audioPlayer: self.audioPlayer!)
            return
        }

        initMedia(url: url, data: data, duration: duration, key: key)
        audioPlayer!.play()
        self.delegate?.didActivateMedia(in: self, audioPlayer: self.audioPlayer!)
    }

    func audioSeekTo(_ seekTo: Float, url: URL?, data: Data?, duration: Int, key: Int) {
        initAudioPlayer()

        initMedia(url: url, data: data, duration: duration, key: key)
        var doPause = false
        if !audioPlayer!.isPlaying {
            audioPlayer!.play()
            doPause = true
        }
        audioPlayer!.position = seekTo
        if doPause {
            audioPlayer!.pause()
        }
        self.delegate?.didSeekMedia(in: self, audioPlayer: self.audioPlayer!, pos: seekTo)
    }
}
