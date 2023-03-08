//
//  BrandingViewController.swift
//  Tinodios
//
//  Copyright © 2023 Tinode LLC. All rights reserved.
//

import TinodiosDB
import UIKit

// Branding configuration VC.
// Allows
class BrandingViewController: UIViewController {
    static let kTinodeHostUriPrefix = "tinode:host/"

    private var qrScanner: QRScanner!

    @IBOutlet weak var configurationCodeField: UITextField!
    @IBOutlet weak var cameraPreviewView: UIView!

    override func viewDidLoad() {
        self.configurationCodeField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        self.qrScanner = QRScanner(embedIn: self.cameraPreviewView, expectedCodePrefix: BrandingViewController.kTinodeHostUriPrefix, delegate: self)
    }

    override func viewDidAppear(_ animated: Bool) {
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
        UiUtils.showToast(message: "Configuring. Config ID: " + code, level: .info)
        SharedUtils.setUpBranding(withConfigurationCode: code)
        self.navigationController?.popViewController(animated: true)
    }
}

extension BrandingViewController: QRScannerDelegate {
    func qrScanner(didScanCode codeValue: String?) {
        guard let code = codeValue else {
            Cache.log.error("Invalid host QR code")
            DispatchQueue.main.async {
                UiUtils.showToast(message: "Invalid Tinode configuration QR code")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
                // Restart QR scanner.
                self?.qrScanner.start()
            }
            return
        }
        handleCodeEntered(code)
    }
}
