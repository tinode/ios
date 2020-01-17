//
//  ImagePreviewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

// Shows full-screen
import UIKit
import TinodeSDK

struct ImagePreviewContent {
    let image: UIImage?
    let imageBits: Data?
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

    var interactor: (MessageBusinessLogic & MessageDataStore)?

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    private func setup() {
        guard let content = self.previewContent, let imageBits = content.imageBits else { return }

        if content.image != nil {
            sendImageBar.delegate = self
        }

        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 8.0

        // FIXME: Replace blank UIImage() with a "broken image" icon.
        imageView.image = content.image != nil ? content.image : (UIImage(data: imageBits) ?? UIImage(named: "broken-image"))

        fileNameLabel.text = content.fileName ?? "undefined"
        contentTypeLabel.text = content.contentType ?? "undefined"
        var sizeString = "?? KB"
        if let size = content.size {
            sizeString = UiUtils.bytesToHumanSize(size)
        }
        if let width = content.width, let height = content.height {
            sizeString += "; \(width)×\(height)"
        }
        sizeLabel.text = sizeString
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
        return previewContent?.image != nil ? sendImageBar : super.inputAccessoryView
    }

    override var canBecomeFirstResponder: Bool {
        return previewContent?.image != nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        self.setInterfaceColors()
    }

    private func setInterfaceColors() {
        if #available(iOS 12.0, *), traitCollection.userInterfaceStyle == .dark {
            self.view.backgroundColor = .black
        } else {
            self.view.backgroundColor = .white
        }
    }

    func viewForZooming(in: UIScrollView) -> UIView? {
        return imageView
    }

    @IBAction func saveImageButtonClicked(_ sender: Any) {
        guard let content = previewContent, let imageBits = content.imageBits else { return }

        let picturesUrl: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = picturesUrl.appendingPathComponent(content.fileName ?? Utils.uniqueFilename(forMime: content.contentType))
        do {
            try FileManager.default.createDirectory(at: picturesUrl, withIntermediateDirectories: true, attributes: nil)
            try imageBits.write(to: destinationURL)
            UiUtils.presentFileSharingVC(for: destinationURL)
        } catch {
            print("Failed to save image as \(destinationURL): \(error.localizedDescription)")
        }
    }
}

extension ImagePreviewController : SendImageBarDelegate {
    func sendImageBar(caption: String?) -> Bool? {
        let mimeType: String = previewContent?.contentType == "image/png" ?  "image/png" : "image/jpeg"

        // Ensure image size in bytes and linear dimensions are under the limits.
        guard let image = previewContent?.image?.resize(width: UiUtils.kMaxBitmapSize, height: UiUtils.kMaxBitmapSize, clip: false)?.resize(byteSize: MessageViewController.kMaxInbandAttachmentSize, asMimeType: mimeType) else { return false }

        guard let bits = image.pixelData(forMimeType: mimeType) else { return false }

        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)

        var msg = Drafty(plainText: " ")
            .insertImage(at: 0, mime: mimeType, bits: bits, width: width, height: height, fname: previewContent?.fileName)
        if let caption = caption, caption.count > 0 {
            msg = msg.appendLineBreak().append(Drafty(plainText: caption))
        }
        return interactor?.sendMessage(content: msg)
    }

    func sendImageBar(textChangedTo text: String) {
        interactor?.sendTypingNotification()
    }
}
