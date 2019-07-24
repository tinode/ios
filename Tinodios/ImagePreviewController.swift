//
//  ImagePreviewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

// Shows full-screen
import UIKit

protocol ImagePreviewLogic: class {

}

class ImagePreviewController : UIViewController {

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var contentTypeLabel: UILabel!
    @IBOutlet weak var fileNameLabel: UILabel!
    @IBOutlet weak var sizeLabel: UILabel!

    var content: ImagePreviewContent? = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    override func viewDidAppear(_ animated: Bool) {
        setup()
    }

    private func setup() {
        guard let content = self.content else { return }

        imageView.image = content.imagePreview
        fileNameLabel.text = content.fileName ?? "undefined"
        contentTypeLabel.text = content.contentType ?? "undefined"
        var sizeString = "?? KB"
        if let size = content.size {
            sizeString = UiUtils.bytesToHumanSize(size)
        }
        if let width = content.width, let height = content.height {
            sizeString += "; \(width) \(height)"
        }
        sizeLabel.text = sizeString
    }

    struct ImagePreviewContent {
        let imagePreview: UIImage?
        let fileName: String?
        let contentType: String?
        let size: Int64?
        let width: Int?
        let height: Int?
    }
}
