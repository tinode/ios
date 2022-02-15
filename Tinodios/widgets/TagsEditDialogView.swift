//
//  TagsEditDialogView.swift
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK
import UIKit

class TagsEditDialogViewController: UIViewController {
    private static let kButtonBorderColor = UIColor.lightGray

    private static let kDefaultMaxTagCount: Int64 = 16

    public typealias CompletionHandler = ((_ newTags: [TinodeTag]) -> Void)

    @IBOutlet weak var alertView: UIView!
    @IBOutlet weak var okButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var tagsEditView: TagsEditView!

    private var initialTags: [TinodeTag] = []
    public var completionHandler: CompletionHandler?

    init(with tags: [TinodeTag]) {
        super.init(nibName: nil, bundle: nil)
        modalTransitionStyle = .crossDissolve
        modalPresentationStyle = .overCurrentContext

        self.initialTags = tags
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        cancelButton.addBorder(side: .top, color: TagsEditDialogViewController.kButtonBorderColor, width: 1)
        cancelButton.addBorder(side: .right, color: TagsEditDialogViewController.kButtonBorderColor, width: 1)
        okButton.addBorder(side: .top, color: TagsEditDialogViewController.kButtonBorderColor, width: 1)

        let maxTagCount = Cache.tinode.getServerLimit(for: Tinode.kMaxTagCount, withDefault: TagsEditDialogViewController.kDefaultMaxTagCount)
        tagsEditView.fontSize = 17
        tagsEditView.layer.cornerRadius = 8
        tagsEditView.layer.borderColor = TagsEditDialogViewController.kButtonBorderColor.cgColor
        tagsEditView.layer.borderWidth = 0.5
        tagsEditView.onShouldAcceptTag = { v in
            // Make sure we don't add more than maxTagCount.
            return v.tagViews.count < maxTagCount
        }
        tagsEditView.onVerifyTag = { (_, tag) in
            return Utils.isValidTag(tag: tag)
        }
        tagsEditView.addTags(initialTags)
        tagsEditView.becomeFirstResponder()
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
        let newTags = tagsEditView.tags
        if !newTags.elementsEqual(initialTags) {
            completionHandler?(newTags)
        }
        self.dismiss(animated: true, completion: nil)
    }
}
