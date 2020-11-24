//
//  ImagePicker.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import MobileCoreServices
import UIKit

public protocol ImagePickerDelegate: class {
    func didSelect(image: UIImage?, mimeType: String?, fileName: String?)
}

open class ImagePicker: NSObject {

    private let pickerController: UIImagePickerController
    private weak var presentationController: UIViewController?
    private weak var delegate: ImagePickerDelegate?

    public init(presentationController: UIViewController, delegate: ImagePickerDelegate, editable: Bool) {
        self.pickerController = UIImagePickerController()

        super.init()

        self.presentationController = presentationController
        self.delegate = delegate

        self.pickerController.delegate = self
        self.pickerController.allowsEditing = editable

        self.pickerController.mediaTypes = [kUTTypeImage as String]
    }

    private func action(for type: UIImagePickerController.SourceType, title: String) -> UIAlertAction? {
        guard UIImagePickerController.isSourceTypeAvailable(type) else {
            return nil
        }

        return UIAlertAction(title: title, style: .default) { [unowned self] _ in
            self.pickerController.sourceType = type
            self.presentationController?.present(self.pickerController, animated: true)
        }
    }

    public func present(from sourceView: UIView) {

        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if let action = self.action(for: .camera, title: "Take photo") {
            alertController.addAction(action)
        }
        if let action = self.action(for: .savedPhotosAlbum, title: "Camera roll") {
            alertController.addAction(action)
        }
        if let action = self.action(for: .photoLibrary, title: "Photo library") {
            alertController.addAction(action)
        }

        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        if UIDevice.current.userInterfaceIdiom == .pad {
            alertController.popoverPresentationController?.sourceView = sourceView
            alertController.popoverPresentationController?.sourceRect = sourceView.bounds
            alertController.popoverPresentationController?.permittedArrowDirections = [.down, .up]
        }

        // Unnecessary empty view is added and animation is disabled because of
        // https://stackoverflow.com/questions/55653187/swift-default-alertviewcontroller-breaking-constraints
        // https://stackoverflow.com/questions/55372093/uialertcontrollers-actionsheet-gives-constraint-error-on-ios-12-2
        // FIXME: Remove the following line and make `animation: true` when Apple fixes the bug.
        alertController.view.addSubview(UIView())
        self.presentationController?.present(alertController, animated: false)
    }

    private func pickerController(_ controller: UIImagePickerController, didSelect image: UIImage?, mimeType mime: String?, fileName fname: String?) {
        controller.dismiss(animated: true, completion: nil)

        self.delegate?.didSelect(image: image, mimeType: mime, fileName: fname)
    }
}

extension ImagePicker: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.pickerController(picker, didSelect: nil, mimeType: nil, fileName: nil)
        picker.dismiss(animated: true, completion: nil)
    }

    public func imagePickerController(_ picker: UIImagePickerController,
                                      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let image = (info[self.pickerController.allowsEditing ? .editedImage : .originalImage] as? UIImage)?.fixedOrientation() else {
            return self.pickerController(picker, didSelect: nil, mimeType: nil, fileName: nil)
        }

        let imageUrl = info[.imageURL] as? NSURL

        // Get mime type and file name
        let urlResourceValues = try? imageUrl?.resourceValues(forKeys: [.typeIdentifierKey, .nameKey])
        let uti = urlResourceValues?[.typeIdentifierKey] as? NSString
        let fname = urlResourceValues?[.nameKey] as? NSString

        let mimeType: String?
        if let uti = uti {
            // Convert UTI string like 'public.jpeg' to MIME type like 'image/jpeg'
            let unmanaged = UTTypeCopyPreferredTagWithClass(uti as CFString, kUTTagClassMIMEType)
            mimeType = unmanaged?.takeRetainedValue() as String?
        } else {
            mimeType = nil
        }

        self.pickerController(picker, didSelect: image, mimeType: mimeType, fileName: fname as String?)
    }
}
