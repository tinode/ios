//
//  ImagePreviewController.swift
//  Tinodios
//
//  Copyright © 2019-2020 Tinode. All rights reserved.
//

// Shows full-screen
import UIKit
import TinodeSDK

struct ImagePreviewContent {
    enum ImageContent {
        case uiimage(UIImage)
        case rawdata(Data)
    }

    let imgContent: ImageContent
    let caption: String?
    let fileName: String?
    let contentType: String?
    let size: Int64?
    let width: Int?
    let height: Int?
}

class ImagePreviewController : UIViewController, UIScrollViewDelegate {

    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var contentTypeLabel: UILabel!
    @IBOutlet weak var fileNameLabel: UILabel!
    @IBOutlet weak var sizeLabel: UILabel!
    @IBOutlet weak var imageDetailsPanel: UIStackView!

    var previewContent: ImagePreviewContent? = nil

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
            // Hide [Save image] button.
            navigationItem.rightBarButtonItem = nil
            // Hide image details panel.
            imageDetailsPanel.bounds = CGRect()
        case .rawdata(let bits):
            // Viewing received image.
            imageView.image = UIImage(data: bits)

            // Fill out details panel for the received image.
            fileNameLabel.text = content.fileName ?? NSLocalizedString("undefined", comment: "Placeholder for missing file name")
            contentTypeLabel.text = content.contentType ?? NSLocalizedString("undefined", comment: "Placeholder for missing file type")
            var sizeString = "?? KB"
            if let size = content.size {
                sizeString = UiUtils.bytesToHumanSize(size)
            }
            if let width = content.width, let height = content.height {
                sizeString += "; \(width)×\(height)"
            }
            sizeLabel.text = sizeString
        }

        if imageView.image == nil {
            imageView.image = UIImage(named: "broken-image")
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
        return previewContent?.imgContent != nil ? sendImageBar : super.inputAccessoryView
    }

    override var canBecomeFirstResponder: Bool {
        return previewContent?.imgContent != nil
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
        guard case let .rawdata(imageBits) = content.imgContent else { return }

        let picturesUrl: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = picturesUrl.appendingPathComponent(content.fileName ?? Utils.uniqueFilename(forMime: content.contentType))
        do {
            try FileManager.default.createDirectory(at: picturesUrl, withIntermediateDirectories: true, attributes: nil)
            try imageBits.write(to: destinationURL)
            UiUtils.presentFileSharingVC(for: destinationURL)
        } catch {
            Cache.log.info("Failed to save image as %@: %@", destinationURL.absoluteString, error.localizedDescription)
        }
    }
}

extension ImagePreviewController : SendImageBarDelegate {
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
            height: Int(image.size.height * image.scale)
        )

        // This notification is received by the MessageViewController.
        NotificationCenter.default.post(name: Notification.Name(MessageViewController.kNotificationSendAttachment), object: content)
        // Return to MessageViewController.
        navigationController?.popViewController(animated: true)
    }
}
