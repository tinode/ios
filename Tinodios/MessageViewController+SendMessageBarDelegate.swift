//
//  MessageViewController+SendMessageBarDelegate.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import MobileCoreServices
import TinodeSDK

extension MessageViewController: SendMessageBarDelegate {
    // Default 256K server limit. Does not account for base64 compression and overhead.
    static let kMaxInbandAttachmentSize: Int64 = 1 << 18
    // Default upload size.
    static let kMaxAttachmentSize: Int64 = 1 << 23

    func sendMessageBar(sendText: String) {
        interactor?.sendMessage(content: Drafty(content: sendText))
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
        if self.sendTypingNotifications {
            interactor?.sendTypingNotification()
        }
    }

    func sendMessageBar(enablePeersMessaging: Bool) {
        if enablePeersMessaging {
            interactor?.enablePeersMessaging()
        }
    }

    func sendMessageBar(recordAudio action: AudioRecordingAction) {
        switch action {
        case .start:
            Cache.mediaRecorder.start()
            print("recording started")
        case .stopAndSend:
            print("end recording audio and send, url=\(Cache.mediaRecorder.recordFileURL ?? URL(fileURLWithPath: "nil"))")
            Cache.mediaRecorder.stop()
            if let recordURL = Cache.mediaRecorder.recordFileURL {
                sendAudioAttachment(url: recordURL, duration: Cache.mediaRecorder.duration!, preview: Data())
            }
        case .cancel:
            Cache.mediaRecorder.stop()
            Cache.mediaRecorder.delete()
            print("cancelled recording")
        default:
            print("some other recording action \(action)")
        }
    }
}

extension MessageViewController: UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true, completion: nil)
        // NOTE(Apple's bug, Tinode's hack):
        // When UIDocumentPickerDelegate is dismissed it keeps the keyboard window
        // active. If then we show a toast, the keyboard window is counted "last"
        // in the window stack and we attempt to present the toast over it.
        // In reality, though, the window turns out at the bottom of the stack
        // and thus the toast ends up covered by the key window and never presented
        // to the user.
        // sendMessageBar.becomeFirstResponder() "fixes" the window stack.
        // This is UGLY because it pops the keyboard. Find a better solution.
        (self.inputAccessoryView as? SendMessageBar)?.inputField.becomeFirstResponder()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // Convert file to Data and attach to message
        do {
            // See comment in documentPickerWasCancelled().
            (self.inputAccessoryView as? SendMessageBar)?.inputField.becomeFirstResponder()

            let bits = try Data(contentsOf: urls[0], options: .mappedIfSafe)
            let fname = urls[0].lastPathComponent
            let mimeType: String = Utils.mimeForUrl(url: urls[0], ifMissing: "application/octet-stream")
            let maxAttachmentSize = Cache.tinode.getServerLimit(for: Tinode.kMaxFileUploadSize, withDefault: MessageViewController.kMaxAttachmentSize)
            guard bits.count <= maxAttachmentSize else {
                UiUtils.showToast(message: String(format: NSLocalizedString("The file size exceeds the limit %@", comment: "Error message"), UiUtils.bytesToHumanSize(maxAttachmentSize)))
                return
            }

            let pendingPreview = (self.inputAccessoryView as! SendMessageBar).pendingPreviewText
            let content = FilePreviewContent(
                data: bits,
                refUrl: urls[0],
                fileName: fname,
                contentType: mimeType,
                size: bits.count,
                pendingMessagePreview: pendingPreview
            )
            performSegue(withIdentifier: "ShowFilePreview", sender: content)
        } catch {
            Cache.log.error("MessageVC - failed to read file: %@", error.localizedDescription)
        }
    }
}

extension MessageViewController: ImagePickerDelegate {
    func didSelect(image: UIImage?, mimeType mime: String?, fileName fname: String?) {
        guard let image = image else { return }

        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)

        let pendingPreview = (self.inputAccessoryView as! SendMessageBar).pendingPreviewText
        let content = ImagePreviewContent(
            imgContent: ImagePreviewContent.ImageContent.uiimage(image),
            caption: nil,
            fileName: fname,
            contentType: mime,
            size: 0,
            width: width,
            height: height,
            pendingMessagePreview: pendingPreview)

        performSegue(withIdentifier: "ShowImagePreview", sender: content)
    }
}
