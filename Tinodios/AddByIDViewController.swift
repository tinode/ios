//
//  AddByIDViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

class AddByIDViewController: UIViewController {

    var tinode: Tinode!
    @IBOutlet weak var idTextField: UITextField!
    @IBOutlet weak var okayButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.idTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        self.tinode = Cache.tinode
        UiUtils.dismissKeyboardForTaps(onView: self.view)
    }

    override func viewDidAppear(_ animated: Bool) {
        self.setInterfaceColors()
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
        UiUtils.clearTextFieldError(textField)
    }
    @IBAction func okayClicked(_ sender: Any) {
        let id = UiUtils.ensureDataInTextField(idTextField)
        guard !id.isEmpty else { return }
        okayButton.isEnabled = false
        // FIXME: this generates an unnecessary network call which fetches topic description.
        // The description is discarded and re-requested as a part of the subsequent {sub} call.
        // Either get rid of the {get} call or save the returned description.
        let getMeta = MsgGetMeta(desc: MetaGetDesc(), sub: nil, data: nil, del: nil, tags: false, cred: false)
        tinode.getMeta(topic: id, query: getMeta).then(
            onSuccess: { [weak self] msg in
                // Valid topic id.
                if let desc = msg?.meta?.desc as? Description<VCard, PrivateType> {
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
}
