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

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "ShowImagePreview" {
            let imageUrl = segue.value(forKey: "imageUrl")

            fileNameLabel.text = segue.value(forKey: "fileName") as? String ?? "undefined"
            contentTypeLabel.text = segue.value(forKey: "contentType") as? String ?? "undefined"
            var sizeString = "?? KB"
            if let size = segue.value(forKey: "size") as? Int64 {
                sizeString = UiUtils.bytesToHumanSize(size)
            }
            if let width = segue.value(forKey: "width") as? Int, let height = segue.value(forKey: "height") as? Int {
                sizeString += "; \(width) \(height)"
            }
            sizeLabel.text = sizeString
        }
    }
}
