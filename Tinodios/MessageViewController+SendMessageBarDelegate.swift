//
//  MessageViewController+SendMessageBarDelegate.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import MobileCoreServices
import TinodeSDK

extension MessageViewController : SendMessageBarDelegate {
    static let kMaxInbandAttachmentSize = 1 << 17
    static let kMaxAttachmentSize = 1 << 23

    func sendMessageBar(sendText: String) -> Bool? {
        return interactor?.sendMessage(content: Drafty(content: sendText))
    }

    func sendMessageBar(attachment: Bool) {
        if attachment {
            attachFile()
        } else {
            attachImage()
        }
    }
    private func attachFile() {
        let types: [String] = [kUTTypeItem, kUTTypeImage] as [String]
        let documentPicker = UIDocumentPickerViewController(documentTypes: types, in: .import)
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .formSheet
        self.present(documentPicker, animated: true, completion: nil)
    }

    private func attachImage() {
        imagePicker?.present(from: self.view)
    }
    func sendMessageBar(textChangedTo text: String) {
        interactor?.sendTypingNotification()
    }

    func sendMessageBar(enablePeersMessaging: Bool) {
        if enablePeersMessaging {
            interactor?.enablePeersMessaging()
        }
    }
}

extension MessageViewController : UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // Convert file to Data and attach to message
        do {
            let bits = try Data(contentsOf: urls[0], options: .mappedIfSafe)
            let fname = urls[0].lastPathComponent
            var mimeType: String? = nil
            if let uti = try urls[0].resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier {
                let unmanaged = UTTypeCopyPreferredTagWithClass(uti as CFString, kUTTagClassMIMEType)
                mimeType = unmanaged?.takeRetainedValue() as String?
            }
            guard bits.count <= MessageViewController.kMaxAttachmentSize else {
                UiUtils.showToast(message: "The file size exceeds the limit \(UiUtils.bytesToHumanSize(Int64(MessageViewController.kMaxAttachmentSize)))")
                return
            }
            if bits.count > MessageViewController.kMaxInbandAttachmentSize {
                self.interactor?.uploadFile(filename: fname, refurl: urls[0], mimeType: mimeType, data: bits)
            } else {
                print("Got data count=\(bits.count), fname='\(fname)', mime: \(mimeType ?? "nil")")
                _ = interactor?.sendMessage(content: Drafty().attachFile(mime: mimeType, bits: bits, fname: fname))
            }
        } catch {
            Cache.log.error("MessageVC - failed to read file: %@", error.localizedDescription)
        }
    }
}

extension MessageViewController : ImagePickerDelegate {
    func didSelect(image: UIImage?, mimeType mime: String?, fileName fname: String?) {
        let mimeType: String = mime == "image/png" ?  mime! : "image/jpeg"

        // Ensure image size in bytes and linear dimensions are under the limits.
        guard let image = image?.resize(width: UiUtils.kMaxBitmapSize, height: UiUtils.kMaxBitmapSize, clip: false)?.resize(byteSize: MessageViewController.kMaxInbandAttachmentSize, asMimeType: mimeType) else { return }

        guard let bits = image.pixelData(forMimeType: mime) else { return }

        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        let content = Drafty.parse(content: " ")
        _ = interactor?.sendMessage(content: content.insertImage(at: 0, mime: mimeType, bits: bits, width: width, height: height, fname: fname ?? "unnamed_image"))
    }
}
