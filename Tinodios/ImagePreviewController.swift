//
//  ImagePreviewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

// Shows full-screen
import UIKit

struct ImagePreviewContent {
    let imagePreview: UIImage?
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

    override func viewDidAppear(_ animated: Bool) {
        setup()
    }

    private func setup() {
        guard let content = self.previewContent else { return }

        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 8.0

        imageView.image = content.imagePreview
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
        print("viewForZooming is called")
        return imageView
    }
}
