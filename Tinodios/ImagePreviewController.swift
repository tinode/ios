//
//  ImagePreviewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

// Shows full-screen
import UIKit

struct ImagePreviewContent {
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

    var previewContent: ImagePreviewContent? = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    private func setup() {
        guard let content = self.previewContent, let imageBits = content.imageBits else { return }

        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 8.0

        imageView.image = UIImage(data: imageBits) ?? UIImage()

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
    }

    func viewForZooming(in: UIScrollView) -> UIView? {
        return imageView
    }

    @IBAction func saveImageButtonClicked(_ sender: Any) {
        guard let content = previewContent, let imageBits = content.imageBits else { return }

        let picturesUrl: URL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
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
