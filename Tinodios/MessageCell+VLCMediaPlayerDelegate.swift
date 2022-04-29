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
        case .playing:
            print("VLCMediaPlayerDelegate: PLAYING")
        case .opening:
            print("VLCMediaPlayerDelegate: OPENING")
        case .error:
            print("VLCMediaPlayerDelegate: ERROR")
        case .buffering:
            print("VLCMediaPlayerDelegate: BUFFERING")
        case .stopped:
            // Must reopen: VLCMedia closes the InputStrem.
            self.mediaStream = nil
            print("VLCMediaPlayerDelegate: STOPPED")
        case .paused:
            print("VLCMediaPlayerDelegate: PAUSED")
        case .ended:
            print("VLCMediaPlayerDelegate: ENDED")
        case .esAdded:
            print("VLCMediaPlayerDelegate: ELEMENTARY STREAM ADDED")
        default:
            break
        }
    }

    func mediaPlayerTimeChanged(_ notification: Notification) {
        guard let player = notification.object as? VLCMediaPlayer else { return }

        print("Time changed: \(player.time.value ?? -1)")
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

    fileprivate func initMedia(url: URL?, data: Data?, duration: Int, seqId: Int, key: Int) {
        if let id = self.mediaId, id == (seqId, key), self.mediaStream != nil {
            // Already properly initialized with the same data.
            return
        }

        print("Reinitializing")

        if let url = url {
            audioPlayer!.media = VLCMedia(url: url)
        } else if let data = data {
            // VLCMedia keep only weak reference to InputStream, must retain a strong reference.
            self.mediaStream = InputStream(data: data)
            audioPlayer!.media = VLCMedia(stream: self.mediaStream!)
        } else {
            Cache.log.error("MessageVC - unable to play audio: no data")
            return
        }
        if audioPlayer!.media.length.intValue <= 0 && duration > 0 {
            audioPlayer!.media.length = VLCTime(int: Int32(duration))
        } else {
            print("Duration not assigned player=\(audioPlayer!.media.length.intValue), app=\(duration)")
        }
        print("Duration: \(audioPlayer!.media.length.value)")
        self.mediaId = (seqId, key)
    }

    func toggleAudioPlay(url: URL?, data: Data?, duration: Int, seqId: Int, key: Int) {
        initAudioPlayer()

        if audioPlayer!.isPlaying {
            audioPlayer!.pause()
            print("Paused")
            return
        }

        initMedia(url: url, data: data, duration: duration, seqId: seqId, key: key)
        print("Playing")
        audioPlayer!.play()
    }

    func audioSeekTo(_ seekTo: Float, url: URL?, data: Data?, duration: Int, seqId: Int, key: Int) {
        initAudioPlayer()

        print("Player is seekable: \(audioPlayer?.isSeekable)")

        initMedia(url: url, data: data, duration: duration, seqId: seqId, key: key)
        var doPause = false
        if audioPlayer!.isPlaying {
            audioPlayer!.play()
            doPause = true
        }
        print("Before seeking \(audioPlayer!.time)")
        audioPlayer!.position = seekTo
        if doPause {
            audioPlayer!.pause()
        }
        print("After seeking \(audioPlayer!.time)")
    }
}
