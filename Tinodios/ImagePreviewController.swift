//
//  ImagePreviewController.swift
//  Tinodios
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

// Shows full-screen
import Kingfisher
import TinodeSDK
import UIKit

struct ImagePreviewContent {
    enum ImageContent {
        case uiimage(UIImage)
        case rawdata(Data?, String?)  // inline data or reference
    }

    let imgContent: ImageContent
    let caption: String?
    let fileName: String?
    let contentType: String?
    let size: Int64?
    let width: Int?
    let height: Int?

    // ReplyTo preview (the user is replying to another message with an image).
    let pendingMessagePreview: NSAttributedString?
}

class ImagePreviewController: UIViewController, UIScrollViewDelegate {

    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var contentTypeLabel: UILabel!
    @IBOutlet weak var fileNameLabel: UILabel!
    @IBOutlet weak var sizeLabel: UILabel!
    @IBOutlet weak var imageDetailsPanel: UIStackView!

    var previewContent: ImagePreviewContent?
    var replyPreviewDelegate: PendingMessagePreviewDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    private func setup() {
        guard let content = self.previewContent else { return }

        switch content.imgContent {
        case .uiimage(let image):
            // Image preview before sending.
            imageView.image = image

            sendImageBar.delegate = self
            sendImageBar.replyPreviewDelegate = replyPreviewDelegate
            sendImageBar.togglePreviewBar(with: content.pendingMessagePreview)
            // Hide [Save image] button.
            navigationItem.rightBarButtonItem = nil
            // Hide image details panel.
            imageDetailsPanel.bounds = CGRect()
        case .rawdata(let bits, let ref):
            let errorImage = UiUtils.placeholderImage(
                named: "broken-image", withBackground: nil,
                width: CGFloat(content.width ?? 64), height: CGFloat(content.height ?? 64))
            // Viewing received image.

            imageView.image = bits != nil ? UIImage(data: bits!) : errorImage

            // Fill out details panel for the received image.
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

            // If we have a reference, kick off the download.
            if let ref = ref, let url = URL(string: ref, relativeTo: Cache.tinode.baseURL(useWebsocketProtocol: false)) {
                self.startDownload(fromUrl: url, onError: errorImage)
            }
            sendImageBar.togglePreviewBar(with: nil)
        }

        if imageView.image == nil {
            imageView.image = UiUtils.placeholderImage(
                named: "broken-image", withBackground: nil,
                width: CGFloat(content.width ?? 64), height: CGFloat(content.height ?? 64))
        }

        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 8.0

        setInterfaceColors()
    }

    /// The `sendImageBar` is used as an optional `inputAccessoryView` in the view controller.
    private lazy var sendImageBar: SendImageBar = {
        let view = SendImageBar()
        view.autoresizingMask = .flexibleHeight
        return view
    }()

    // This makes input bar visible.
    override var inputAccessoryView: UIView? {
        return previewContent?.imgContent != nil && sendImageBar.delegate != nil ? sendImageBar : super.inputAccessoryView
    }

    override var canBecomeFirstResponder: Bool {
        return previewContent?.imgContent != nil && sendImageBar.delegate != nil
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

    func viewForZooming(in: UIScrollView) -> UIView? {
        return imageView
    }

    @IBAction func saveImageButtonClicked(_ sender: Any) {
        guard let content = previewContent else { return }
        guard case let .rawdata(imageBits, ref) = content.imgContent else { return }

        let picturesUrl: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = picturesUrl.appendingPathComponent(content.fileName ?? Utils.uniqueFilename(forMime: content.contentType))
        let data = ref != nil ? self.imageView.image?.pixelData(forMimeType: content.contentType) : imageBits
        guard let data = data else { return }
        do {
            try FileManager.default.createDirectory(at: picturesUrl, withIntermediateDirectories: true, attributes: nil)
            try data.write(to: destinationURL)
            UiUtils.presentFileSharingVC(for: destinationURL)
        } catch {
            Cache.log.info("Failed to save image as %@: %@", destinationURL.absoluteString, error.localizedDescription)
        }
    }

    // Downloads image from the provided url and displays it to the user.
    private func startDownload(fromUrl url: URL, onError errorImage: UIImage) {
        let modifier = AnyModifier { request in
            var request = request
            LargeFileHelper.addCommonHeaders(to: &request, using: Cache.tinode)
            return request
        }

        KingfisherManager.shared.retrieveImage(with: url.downloadURL, options: [.requestModifier(modifier)], completionHandler: { result in
            switch result {
            case .success(let value):
                self.imageView.image = value.image
            case .failure(let error):
                self.imageView.image = errorImage
                Cache.log.info("Failed to download image '%@': %d", url.absoluteString, error.errorCode)
            }
        })
    }
}

extension ImagePreviewController: SendImageBarDelegate {
    func sendImageBar(caption: String?) {
        guard let originalContent = self.previewContent else { return }
        guard case let .uiimage(originalImage) = originalContent.imgContent else { return }

        let mimeType = originalContent.contentType == "image/png" ?  "image/png" : "image/jpeg"
        // Ensure image linear dimensions are under the limits.
        guard let image = originalImage.resize(width: UiUtils.kMaxBitmapSize, height: UiUtils.kMaxBitmapSize, clip: false) else { return }

        let content = ImagePreviewContent(
            imgContent: ImagePreviewContent.ImageContent.uiimage(image),
            caption: caption,
            fileName: originalContent.fileName,
            contentType: mimeType,
            size: -1,
            width: Int(image.size.width * image.scale),
            height: Int(image.size.height * image.scale),
            pendingMessagePreview: nil
        )

        // This notification is received by the MessageViewController.
        NotificationCenter.default.post(name: Notification.Name(MessageViewController.kNotificationSendAttachment), object: content)
        // Return to MessageViewController.
        navigationController?.popViewController(animated: true)
    }
    func dismissPreview() {
        self.replyPreviewDelegate?.dismissPendingMessagePreview()
    }
}
