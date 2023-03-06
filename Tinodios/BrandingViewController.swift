//
//  BrandingViewController.swift
//  Tinodios
//
//  Copyright © 2023 Tinode LLC. All rights reserved.
//

import UIKit

class BrandingViewController: UIViewController {
    static let kTinodeHostUriPrefix = "tinode:host/"

    private var qrScanner: QRScanner!

    @IBOutlet weak var configurationCodeField: UITextField!
    @IBOutlet weak var cameraPreviewView: UIView!

    override func viewDidLoad() {
        self.configurationCodeField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        self.qrScanner = QRScanner(embedIn: self.cameraPreviewView, expectedCodePrefix: BrandingViewController.kTinodeHostUriPrefix, delegate: self)
        self.qrScanner.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.qrScanner.stop()
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        textField.clearErrorSign()
    }

    @IBAction func okayClicked(_ sender: Any) {
        let code = UiUtils.ensureDataInTextField(configurationCodeField)
        guard !code.isEmpty else {
            return
        }
        handleCodeEntered(code)
    }

    private func handleCodeEntered(_ code: String) {
        print("code:", code)
    }
}

extension BrandingViewController: QRScannerDelegate {
    func qrScanner(didScanCode codeValue: String?) {
        guard let code = codeValue else {
            Cache.log.error("Invalid QR code")
            return
        }
        handleCodeEntered(code)
    }
}
