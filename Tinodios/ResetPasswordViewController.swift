//
//  ResetPasswordViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

class ResetPasswordViewController : UIViewController {
    @IBOutlet weak var credentialTextField: UITextField!
    @IBOutlet weak var requestButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        UiUtils.dismissKeyboardForTaps(onView: self.view)
    }

    override func viewDidAppear(_ animated: Bool) {
        self.setInterfaceColors()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if self.isMovingFromParent {
            // If the user's logged in and is voluntarily leaving the ResetPassword VC
            // by hitting the Back button.
            let tinode = Cache.tinode
            if tinode.isConnectionAuthenticated || tinode.myUid != nil {
                tinode.logout()
            }
        }
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

    @IBAction func credentialTextChanged(_ sender: Any) {
        if credentialTextField.rightView != nil {
            UiUtils.clearTextFieldError(credentialTextField)
        }
    }

    @IBAction func requestButtonClicked(_ sender: Any) {
        UiUtils.clearTextFieldError(credentialTextField)
        let input = UiUtils.ensureDataInTextField(credentialTextField)
        guard let credential = ValidatedCredential.parse(from: input.lowercased()) else {
            UiUtils.markTextFieldAsError(self.credentialTextField)
            UiUtils.showToast(message: NSLocalizedString("Enter a valid credential (phone or email).", comment: "Toast error message"))
            return
        }
        let normalized: String
        switch credential {
        case let .email(str): normalized = str
        case let .phoneNum(str): normalized = str
        default: return
        }

        let tinode = Cache.tinode
        UiUtils.toggleProgressOverlay(in: self, visible: true, title: NSLocalizedString("Requesting...", comment: "Progress overlay"))
        do {
            try tinode.connectDefault(inBackground: false)?
                .thenApply({ _ in
                    return tinode.requestResetPassword(method: credential.methodName(), newValue: normalized)
                })
                .thenApply({ _ in
                    DispatchQueue.main.async { UiUtils.showToast(message: NSLocalizedString("Message with instructions sent to the provided address.", comment: "Toast info")) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
                        self?.navigationController?.popViewController(animated: true)
                    }
                    return nil
                })
                .thenCatch(UiUtils.ToastFailureHandler)
                .thenFinally {
                    UiUtils.toggleProgressOverlay(in: self, visible: false)
                }
        } catch {
            UiUtils.toggleProgressOverlay(in: self, visible: false)
            UiUtils.showToast(message: String(format: NSLocalizedString("Request failed: %@", comment: "Error message"), error.localizedDescription))
        }
    }
}
