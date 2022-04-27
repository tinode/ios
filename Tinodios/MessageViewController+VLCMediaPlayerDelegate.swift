//
//  MessageViewController+VLCMediaPlayerDelegate.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import MobileCoreServices
import MobileVLCKit
import UIKit

extension MessageViewController: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ notification: Notification!) {
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
    fileprivate func initMedia(url: URL?, data: Data?, seqId: Int, key: Int) {
        if let id = self.mediaId, id == (seqId, key) {
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
            Cache.log.error("MessageVC - unable to play audio: no data")
            return
        }

        self.mediaId = (seqId, key)
    }

    func toggleAudioPlay(url: URL?, data: Data?, seqId: Int, key: Int) {
        initAudioPlayer()

        if audioPlayer!.isPlaying {
            audioPlayer!.pause()
            return
        }

        initMedia(url: url, data: data, seqId: seqId, key: key)
        audioPlayer!.play()
    }

    func audioSeekTo(_ seekTo: Float, url: URL?, data: Data?, seqId: Int, key: Int) {
        initAudioPlayer()

        initMedia(url: url, data: data, seqId: seqId, key: key)
        audioPlayer!.position = seekTo
        // audioPlayer!.play()
    }
}
