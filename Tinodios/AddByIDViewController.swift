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
        self.tinode = Cache.getTinode()
    }
    @objc func textFieldDidChange(_ textField: UITextField) {
        UiUtils.clearTextFieldError(textField)
    }
    @IBAction func okayClicked(_ sender: Any) {
        let id = UiUtils.ensureDataInTextField(idTextField)
        guard !id.isEmpty else { return }
        okayButton.isEnabled = false
        let getMeta = MsgGetMeta(desc: MetaGetDesc(ims: Date.distantPast), sub: nil, data: nil, del: nil, tags: false)
        _ = try? tinode.getMeta(topic: id, query: getMeta)?.then(
            onSuccess: { [weak self] msg in
                // Valid topic id.
                self?.presentChatReplacingCurrentVC(with: id)
                return nil
            },
            onFailure: { [weak self] err in
                print("err = \(err)")
                if let e = err as? TinodeError {
                    if case TinodeError.serverResponseError(let code, let text, _) = e {
                        DispatchQueue.main.async {
                        self?.showToast(message: "Invalid topic id: \(code) \(text)")
                        }
                    }
                }
                return nil
            })?.thenFinally(finally: { [weak self] in
                DispatchQueue.main.async {
                    self?.okayButton.isEnabled = true
                }
                return nil
            })
    }
}
