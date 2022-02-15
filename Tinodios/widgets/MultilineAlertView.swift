//
//  MultilineAlertView.swift
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import TinodeSDK
import UIKit

class MultilineAlertViewController: UIViewController {
    private static let kButtonBorderColor = UIColor.lightGray

    @IBOutlet weak var alertView: UIView!
    @IBOutlet weak var okButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var textEditView: UITextView!
    @IBOutlet weak var titleLabel: UILabel!

    private var initialText: String = ""

    public typealias CompletionHandler = ((_: String?) -> Void)
    public var completionHandler: CompletionHandler?

    init(with text: String?, placeholder: String? = nil) {
        super.init(nibName: nil, bundle: nil)
        modalTransitionStyle = .crossDissolve
        modalPresentationStyle = .overCurrentContext

        self.initialText = text ?? ""
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        titleLabel.text = title
        cancelButton.addBorder(side: .top, color: MultilineAlertViewController.kButtonBorderColor, width: 0.5)
        cancelButton.addBorder(side: .right, color: MultilineAlertViewController.kButtonBorderColor, width: 0.5)
        okButton.addBorder(side: .top, color: MultilineAlertViewController.kButtonBorderColor, width: 0.5)

        textEditView.font = UIFont.systemFont(ofSize: 16)
        textEditView.layer.cornerRadius = 8
        textEditView.text = initialText
        textEditView.layer.borderColor = MultilineAlertViewController.kButtonBorderColor.cgColor
        textEditView.layer.borderWidth = 0.5
        textEditView.becomeFirstResponder()
    }

    func show(over viewController: UIViewController?) {
        guard let viewController = viewController else { return }
        viewController.present(self, animated: true, completion: nil)
    }

    // MARK: - Button clicks
    @IBAction func cancelClicked(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }

    @IBAction func okayClicked(_ sender: Any) {
        if (textEditView.text ?? "") != initialText {
            completionHandler?(textEditView.text)
        }
        self.dismiss(animated: true, completion: nil)
    }
}

