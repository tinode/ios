//
//  AddByIDViewController.swift
//  Tinodios
//
//  Copyright © 2019-2023 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

class AddByIDViewController: UIViewController {
    static let kTopicUriPrefix = "tinode:topic/"

    private var qrScanner: QRScanner?
    private var tinode: Tinode!

    @IBOutlet weak var showCodeButton: UIButton!
    @IBOutlet weak var scanCodeButton: UIButton!

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var idTextField: UITextField!
    @IBOutlet weak var okayButton: UIButton!
    @IBOutlet weak var qrcodeImageView: UIImageView!
    @IBOutlet weak var cameraPreviewView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.idTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        self.tinode = Cache.tinode
        UiUtils.dismissKeyboardForTaps(onView: self.view)

        showCodeButton.tintColor = UIColor.label.inverted
        if let myUid = tinode.myUid {
            qrcodeImageView.image = generateQRCode(from: AddByIDViewController.kTopicUriPrefix + myUid)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        self.setInterfaceColors()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        qrScanner?.stop()
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

    @objc func textFieldDidChange(_ textField: UITextField) {
        textField.clearErrorSign()
    }

    @IBAction func okayClicked(_ sender: Any) {
        let id = UiUtils.ensureDataInTextField(idTextField)
        guard !id.isEmpty else { return }
        okayButton.isEnabled = false
        // FIXME: this generates an unnecessary network call which fetches topic description.
        // The description is discarded and re-requested as a part of the subsequent {sub} call.
        // Either get rid of the {get} call or save the returned description.
        handleCodeEntered(id)
    }

    @IBAction func showCodePressed(_ sender: Any) {
        if let cs = self.qrScanner {
            cs.stop()
            self.qrScanner = nil
        }

        cameraPreviewView.isHidden = true
        qrcodeImageView.isHidden = false

        titleLabel.text = NSLocalizedString("My Code", comment: "Title for displaying a QR Code")


        showCodeButton.tintColor = UIColor.label.inverted
        showCodeButton.backgroundColor = UIColor.link
        scanCodeButton.tintColor = UIColor.link
        scanCodeButton.backgroundColor = UIColor.systemBackground
    }

    @IBAction func scanCodePressed(_ sender: Any) {
        cameraPreviewView.isHidden = false
        qrcodeImageView.isHidden = true

        scanQRCode()

        titleLabel.text = NSLocalizedString("Scan Code", comment: "Title for camera preview when scanning a QR code")

        showCodeButton.tintColor = UIColor.link
        showCodeButton.backgroundColor = UIColor.systemBackground
        scanCodeButton.tintColor = UIColor.label.inverted
        scanCodeButton.backgroundColor = UIColor.link
    }

    func handleCodeEntered(_ id: String) {
        let getMeta = MsgGetMeta(desc: MetaGetDesc(), sub: nil, data: nil, del: nil, tags: false, cred: false)
        tinode.getMeta(topic: id, query: getMeta).then(
            onSuccess: { [weak self] msg in
                // Valid topic id.
                if let desc = msg?.meta?.desc as? Description<TheCard, PrivateType> {
                    ContactsManager.default.processDescription(uid: id, desc: desc)
                }
                self?.presentChatReplacingCurrentVC(with: id)
                return nil
            },
            onFailure: { err in
                if let e = err as? TinodeError {
                    if case TinodeError.serverResponseError(let code, let text, _) = e {
                        DispatchQueue.main.async {
                            UiUtils.showToast(message: String(format: NSLocalizedString("Invalid group ID: %d (%@)", comment: "Error message"), code, text))
                        }
                    }
                }
                return nil
            }).thenFinally({ [weak self] in
                DispatchQueue.main.async {
                    self?.okayButton.isEnabled = true
                }
            })
    }

    func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: String.Encoding.ascii)

        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            let transform = CGAffineTransform(scaleX: 3, y: 3)

            if let output = filter.outputImage?.transformed(by: transform) {
                return UIImage(ciImage: output)
            }
        }

        return nil
    }

    func scanQRCode() {
        if qrScanner == nil {
            qrScanner = QRScanner(embedIn: self.cameraPreviewView, expectedCodePrefix: AddByIDViewController.kTopicUriPrefix, delegate: self)
            qrScanner?.start()
        }
    }
}

extension AddByIDViewController: QRScannerDelegate {
    func qrScanner(didScanCode codeValue: String?) {
        guard let code = codeValue else {
            Cache.log.error("Invalid Tinode topic QR code")
            DispatchQueue.main.async {
                UiUtils.showToast(message: "Invalid Tinode topic QR code")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
                // Restart QR scanner.
                self?.qrScanner?.start()
            }
            return
        }
        handleCodeEntered(code)
    }
}
