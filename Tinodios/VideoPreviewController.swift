//
//  VideoPreviewController.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import MobileVLCKit
import UIKit

struct VideoPreviewContent {
    enum VideoSource {
        case local(URL, UIImage?)  // newly picked video: local video url, preview/poster
        case remote(Data?, String?)  // existing message: inline data or reference
    }

    let videoSrc: VideoSource
    // Video duration in milliseconds.
    let duration: Int
    let fileName: String?
    // Video mime type.
    let contentType: String?
    // Video file size.
    let size: Int64?
    let width: Int?
    let height: Int?
    // Text annotation.
    let caption: String?

    // ReplyTo preview (the user is replying to another message with a video).
    let pendingMessagePreview: NSAttributedString?
}

class VideoPreviewController: UIViewController {
    @IBOutlet weak var videoView: UIView!
    @IBOutlet weak var fileNameLabel: UILabel!
    @IBOutlet weak var contentTypeLabel: UILabel!
    @IBOutlet weak var sizeLabel: UILabel!

    @IBOutlet weak var videoSlider: UISlider!
    @IBOutlet weak var currentTimeLabel: UILabel!
    @IBOutlet weak var durationLabel: UILabel!
    @IBOutlet weak var controlsView: UIView!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var spinner: UIActivityIndicatorView!

    private let player = VLCMediaPlayer()
    private let thumbnailer = ThumbnailFetcher()

    var previewContent: VideoPreviewContent?
    var replyPreviewDelegate: PendingMessagePreviewDelegate?

    var duration: Int = 0 {
        didSet {
            let success = duration != 0
            videoSlider.isEnabled = success
            durationLabel.text = duration > 0 ? AbstractFormatter.millisToTime(millis: duration, fixedMin: true) : "--:--"
        }
    }

    private class ThumbnailFetcher: VLCMediaThumbnailerDelegate {
        enum State {
            case none
            case fetching
            case done(CGImage?)
        }
        var state: State = .none
        var thumbnailer: VLCMediaThumbnailer!
        var completion: ((CGImage?) -> Void)?

        func startFetching(fromMedia media: VLCMedia) {
            guard case .none = state else { return }
            state = .fetching
            thumbnailer = VLCMediaThumbnailer(media: media, andDelegate: self)
            thumbnailer.fetchThumbnail()
        }

        func dismiss() {
            state = .done(nil)
        }

        func getThumbmail(completionHandler: @escaping (CGImage?) -> Void) {
            switch state {
            case .none:
                completionHandler(nil)
            case .fetching:
                completion = completionHandler
            case .done(let th):
                completionHandler(th)
            }
        }

        func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
            Cache.log.error("Thumbnail creation failed: timed out")
            state = .done(nil)
            completion?(nil)
        }

        func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
            state = .done(thumbnail)
            completion?(thumbnail)
        }
    }

    private func setup() {
        guard let content = self.previewContent else { return }

        var url: URL?
        var stream: Stream?
        switch content.videoSrc {
        case .local(let videoUrl, _):
            url = videoUrl
            sendVideoBar.delegate = self

            sendVideoBar.replyPreviewDelegate = replyPreviewDelegate
            // Hide [Save video] button.
            navigationItem.rightBarButtonItem = nil
            // Hide image details panel.
            //imageDetailsPanel.bounds = CGRect()
            break
        case .remote(let bits, let ref):
            if let ref = ref, let tinodeUrl = URL(string: ref, relativeTo: Cache.tinode.baseURL(useWebsocketProtocol: false)) {
                url = Cache.tinode.addAuthQueryParams(tinodeUrl)
            } else if let bits = bits, !bits.isEmpty {
                stream = InputStream(data: bits)
            } else {
                return
            }
        }
        sendVideoBar.togglePreviewBar(with: content.pendingMessagePreview)
        self.duration = content.duration

        // Fill out details panel for the received video.
        fileNameLabel.text = content.fileName ?? NSLocalizedString("undefined", comment: "Placeholder for missing file name")
        contentTypeLabel.text = content.contentType ?? NSLocalizedString("undefined", comment: "Placeholder for missing file type")

        var sizeString = "?? KB"
        if let size = content.size {
            sizeString = UiUtils.bytesToHumanSize(size)
        }
        if let width = content.width, let height = content.height {
            sizeString += "; \(width)×\(height)"
        } else {
            sizeString += "; ??×??"
        }
        sizeLabel.text = sizeString
        currentTimeLabel.text = "--:--"

        updatePlayPauseButton(isPlaying: false)

        player.drawable = videoView
        var media: VLCMedia
        if let url = url {
            media = VLCMedia(url: url)
        } else if let stream = stream as? InputStream {
            media = VLCMedia(stream: stream)
        } else {
            DispatchQueue.main.async { UiUtils.showToast(message: "Invalid input") }
            return
        }
        player.media = media
        player.delegate = self
        player.play()

        setInterfaceColors()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player.stop()
    }

    /// The `sendImageBar` is used as an optional `inputAccessoryView` in the view controller.
    private lazy var sendVideoBar: SendImageBar = {
        let view = SendImageBar()
        view.autoresizingMask = .flexibleHeight
        view.togglePreviewBar(with: nil)
        view.inputField.placeholderText = "Video caption"
        return view
    }()

    // This makes input bar visible.
    override var inputAccessoryView: UIView? {
        //return super.inputAccessoryView
        //return sendVideoBar
        return previewContent?.videoSrc != nil && sendVideoBar.delegate != nil ? sendVideoBar : super.inputAccessoryView
    }

    override var canBecomeFirstResponder: Bool {
        return previewContent?.videoSrc != nil && sendVideoBar.delegate != nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        self.setInterfaceColors()
    }

    private func setInterfaceColors() {
        if traitCollection.userInterfaceStyle == .dark {
            self.view.backgroundColor = .black
        } else {
            self.view.backgroundColor = .white
        }
    }

    private func updatePlayPauseButton(isPlaying: Bool) {
        let im = UIImage(systemName: isPlaying ? "pause.fill" : "play.fill",
                         withConfiguration: UIImage.SymbolConfiguration(pointSize: 70, weight: .regular, scale: .large))
        playPauseButton.setImage(im, for: .normal)
        if isPlaying {
            UIView.animate(withDuration: 1) {
                self.playPauseButton.alpha = 0.2
            }
        } else {
            self.playPauseButton.alpha = 1
        }
    }

    @IBAction func playPauseClicked(_ sender: Any) {
        if player.state == .ended || player.state == .stopped {
            player.stop()
            player.position = 0
            player.play()
            return
        }

        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    @IBAction func videoSliderChanged(_ sender: Any) {
        guard self.duration > 0 && player.isSeekable else { return }
        let value = (sender as! UISlider).value
        player.position = value
    }

    @IBAction func saveVideoButtonClicked(_ sender: Any) {
        guard let content = previewContent, case let .remote(bits, ref) = content.videoSrc else { return }

        let downloadBtn = sender as! UIBarButtonItem
        let picturesUrl: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = picturesUrl.appendingPathComponent(content.fileName ?? Utils.uniqueFilename(forMime: content.contentType))

        if let ref = ref, let url = URL(string: ref, relativeTo: Cache.tinode.baseURL(useWebsocketProtocol: false)) {
            downloadBtn.isEnabled = false
            Cache.getLargeFileHelper().startDownload(from: url) { _ in
                downloadBtn.isEnabled = true
            }
        } else if let bits = bits {
            defer { downloadBtn.isEnabled = true }
            do {
                downloadBtn.isEnabled = false
                try FileManager.default.createDirectory(at: picturesUrl, withIntermediateDirectories: true, attributes: nil)
                try bits.write(to: destinationURL)
                UiUtils.presentFileSharingVC(for: destinationURL)
            } catch {
                Cache.log.info("Failed to save video as %@: %@", destinationURL.absoluteString, error.localizedDescription)
            }
        }
    }

    @IBAction func muteButtonClicked(_ sender: Any) {
        if let btn = sender as? UIButton, let audio = player.audio {
            let isMuted = audio.isMuted
            audio.isMuted = !isMuted

            let im = UIImage(systemName: !isMuted ? "speaker.slash.fill" : "speaker.fill")
            btn.setImage(im, for: .normal)
        }
    }
}

extension VideoPreviewController: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        switch player.state {
        case .playing:
            // Auto-play for remote videos only.
            var shouldPause = false
            if case .none = thumbnailer.state {
                if case .local(_, _) = previewContent!.videoSrc {
                    // Video's just started playing.
                    thumbnailer.startFetching(fromMedia: player.media!)
                    shouldPause = true
                } else {
                    thumbnailer.dismiss()
                }
                // Maybe update duration.
                if duration == 0 {
                    duration = Int(truncating: player.media!.length.value ?? 0)
                }
                // Set initial time.
                setTime(VLCTime(number: 0))
            }
            print("playing")
            spinner.stopAnimating()
            spinner.isHidden = true
            controlsView.backgroundColor = .clear
            controlsView.alpha = 1
            playPauseButton.isHidden = false
            if shouldPause {
                playPauseClicked(playPauseButton!)
            }
            updatePlayPauseButton(isPlaying: !shouldPause)
        case .opening:
            print("opening")
            controlsView.backgroundColor = .white
            controlsView.alpha = 0.5
            spinner.startAnimating()
            spinner.isHidden = false
        case .buffering:
            print("buffering")
        case .error:
            spinner.stopAnimating()
            spinner.isHidden = true
            controlsView.backgroundColor = .clear
            controlsView.alpha = 1
            playPauseButton.isHidden = false
            UiUtils.showToast(message: "Video playback error")
        case .ended:
            // Update slider position and ts label
            // in case the corresponding VLCMediaPlayer event doesn't fire for whatever reason.
            videoSlider.value = 1
            currentTimeLabel.text = self.durationLabel.text
            fallthrough
        case .stopped, .paused:
            updatePlayPauseButton(isPlaying: false)
        default:
            break
        }
    }

    private func setTime(_ time: VLCTime) {
        guard let ts = time.value else { return }
        if self.duration > 0 {
            videoSlider.value = Float(truncating: ts) / Float(self.duration)
        }
        currentTimeLabel.text = time.stringValue
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        setTime(player.time)
    }
}

extension VideoPreviewController: SendImageBarDelegate {
    func sendImageBar(caption: String?) {
        guard let originalContent = self.previewContent,
              case .local(let url, _) = originalContent.videoSrc,
              let media = player.media,
              let mimeType = originalContent.contentType else { return }

        let size = player.videoSize
        thumbnailer.getThumbmail { thumbnail in
            var preview: UIImage?
            if let th = thumbnail {
                preview = UIImage(cgImage: th)
            }
            let content2 = VideoPreviewContent(
                videoSrc: .local(url, preview),
                duration: Int(truncating: media.length.value ?? 0),
                fileName: originalContent.fileName,
                contentType: mimeType,
                size: 0,
                width: Int(size.width),
                height: Int(size.height),
                caption: caption,
                pendingMessagePreview: nil
            )

            // This notification is received by the MessageViewController.
            NotificationCenter.default.post(name: Notification.Name(MessageViewController.kNotificationSendAttachment), object: content2)
            // Return to MessageViewController.
            self.navigationController?.popViewController(animated: true)
        }
    }

    func dismissPreview() {
        self.replyPreviewDelegate?.dismissPendingMessagePreview()
    }
}
