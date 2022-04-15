//
//  MessageViewController+AVAudioPlayerDelegate.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import UIKit
import AVFoundation
import Foundation
import MobileCoreServices

extension MessageViewController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully: Bool) {
        print("Audio play finished")
    }
    func audioPlayerDecodeErrorDidOccur(_: AVAudioPlayer, error: Error?) {
        print("Audio play error \(error)")
    }

    func stopAudio() {
        if let player = audioPlayer {
            if player.isPlaying {
                player.stop()
            }
        }
    }

    func playAudio(url: URL? = nil, data: Data? = nil, mimeType: String?) {
        let uti: String?
        if let mimeType = mimeType {
            uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType as CFString, nil)?.takeRetainedValue() as String?
        } else {
            uti = nil
        }

        if let url = url {
            audioPlayer = try? AVAudioPlayer(contentsOf: url, fileTypeHint: uti)
        } else if let data = data {
            audioPlayer = try? AVAudioPlayer(data: data, fileTypeHint: uti)
        }
        audioPlayer?.delegate = self
        print("Play audio url=\(url), data=\(data), mime=\(uti) player is \(audioPlayer == nil ? "nil" : " NOT nil")")

        audioPlayer?.play()
    }
}
