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

    @IBAction func requestButtonClicked(_ sender: Any) {
        let input = UiUtils.ensureDataInTextField(credentialTextField)
        guard let credential = ValidatedCredential.parse(from: input) else { return }
        let normalized: String
        switch credential {
        case let .email(str): normalized = str
        case let .phoneNum(str): normalized = str
        default: return
        }

        let tinode = Cache.getTinode()
        UiUtils.toggleProgressOverlay(in: self, visible: true, title: "Requesting...")
        do {
            try tinode.connectDefault()?
                .thenApply(onSuccess: { _ in
                    return tinode.requestResetPassword(method: credential.methodName(), newValue: normalized)
                })?
                .thenCatch(onFailure: UiUtils.ToastFailureHandler)?
                .thenFinally {
                    UiUtils.toggleProgressOverlay(in: self, visible: false)
                }
        } catch {
            UiUtils.toggleProgressOverlay(in: self, visible: false)
            UiUtils.showToast(message: "Request failed: \(error.localizedDescription)")
        }
    }
}
