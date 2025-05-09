//
//  TopicGeneralViewController.swift
//
//  Copyright © 2022-2025 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

class TopicGeneralViewController: UITableViewController {

    private static let kSectionBasic = 0
    // Avatar = 0
    private static let kSectionBasicTitle = 1
    private static let kSectionBasicAlias = 2
    private static let kSectionBasicPrivate = 3
    private static let kSectionBasicDescription = 4

    private static let kSectionActions = 1
    private static let kSectionActionsManageTags = 0

    /// Maximum length of user name, topic title, and private comment.
    private static let kMaxTitleLength = 60
    /// Maximum length of topic description.
    private static let kMaxDescriptionLength = 360

    var topicName = ""
    private var topic: DefaultComTopic!
    private var tinode: Tinode!
    private var imagePicker: ImagePicker!

    private var aliasTesterTimer: Timer?

    private static let kDescriptionPlaceholder = NSLocalizedString("Optional description", comment: "Placeholder for missing topic description")

    @IBOutlet weak var actionManageTags: UITableViewCell!

    @IBOutlet weak var topicTitleTextField: UITextField!
    @IBOutlet weak var aliasTextField: UITextField!
    @IBOutlet weak var topicDescriptTextView: UITextView!
    @IBOutlet weak var topicPrivateTextField: UITextField!

    @IBOutlet weak var avatarImage: RoundImageView!
    @IBOutlet weak var loadAvatarButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        reloadData()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        reloadData()
    }

    private func setup() {
        self.tinode = Cache.tinode
        self.topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic
        guard self.topic != nil else {
            return
        }

        if self.topic.isGrpType {
            loadAvatarButton.isHidden = !topic.isManager
        } else {
            loadAvatarButton.isHidden = true
        }

        self.imagePicker = ImagePicker(presentationController: self, delegate: self, editable: true)

        topicTitleTextField.delegate = self
        topicTitleTextField.tag = TopicGeneralViewController.kSectionBasicTitle

        aliasTextField.delegate = self
        aliasTextField.tag = TopicGeneralViewController.kSectionBasicAlias
        aliasTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)

        topicPrivateTextField.delegate = self
        topicPrivateTextField.tag = TopicGeneralViewController.kSectionBasicPrivate

        topicDescriptTextView.delegate = self
        topicDescriptTextView.tag = TopicGeneralViewController.kSectionBasicDescription

        topicPrivateTextField.isEnabled = true
        if topic.isOwner {
            topicTitleTextField.isEnabled = true
            aliasTextField.isEnabled = true
            topicDescriptTextView.isUserInteractionEnabled = true
        } else {
            topicTitleTextField.isEnabled = false
            aliasTextField.isEnabled = false
            topicDescriptTextView.isUserInteractionEnabled = false
        }
        UiUtils.setupTapRecognizer(
            forView: actionManageTags,
            action: #selector(TopicGeneralViewController.manageTagsClicked),
            actionTarget: self)
    }

    private func reloadData() {
        // Title
        if topic.isSlfType {
            topicTitleTextField.text = NSLocalizedString("Saved messages", comment: "Title of slf topic")
        } else {
            topicTitleTextField.text = topic.pub!.fn
        }

        // Private comment
        if !topic.isSlfType {
            topicPrivateTextField.text = topic.comment
        }

        // Description
        if topic.isSlfType {
            topicDescriptTextView.text = NSLocalizedString("Notes, messages, links, files saved for posterity", comment: "Explanation for Saved messages topic")
        } else if (topic.pub?.note ?? "").isEmpty {
            if topic.isOwner {
                topicDescriptTextView.textColor = .placeholderText
                topicDescriptTextView.text = TopicGeneralViewController.kDescriptionPlaceholder
            }
        } else {
            topicDescriptTextView.text = topic.pub!.note
        }

        if !topic.isSlfType {
            aliasTextField.leftView = UIImageView(image: UIImage(systemName: "at"))
            aliasTextField.leftViewMode = .always
            aliasTextField.text = topic.alias
        }

        avatarImage.set(pub: topic.pub, id: topic.name, deleted: topic.deleted)
        avatarImage.letterTileFont = self.avatarImage.letterTileFont.withSize(CGFloat(50))
    }

    @IBAction func loadAvatarClicked(_ sender: Any) {
        imagePicker.present(from: self.view)
    }

    @IBAction func doneEditingClicked(_ sender: Any) {
        var pub: TheCard? = nil
        if let title = topicTitleTextField.text, title != topic.pub?.fn {
            pub = TheCard(fn: title)
        }
        let desc = topicDescriptTextView.text
        if desc != self.topic.pub?.note {
            pub = pub ?? TheCard()
            if (desc ?? "").isEmpty || desc == TopicGeneralViewController.kDescriptionPlaceholder {
                pub!.note = Tinode.kNullValue
            } else {
                pub!.note = desc
            }
        }
        var priv: PrivateType? = nil
        if let comment = topicPrivateTextField.text, self.topic.comment! != comment {
            priv = PrivateType()
            priv!.comment = comment.isEmpty ? Tinode.kNullValue : comment
        }
        var tags: [String]? = nil
        if let alias = self.aliasTextField.text, !alias.isEmpty {
            tags = Tinode.setUniqueTag(tags: self.topic.tags, uniqueTag: "\(Tinode.kTagAlias)\(alias)")
        } else {
            tags = Tinode.clearTagPrefix(tags: self.topic.tags, prefix: Tinode.kTagAlias)
        }
        if tags != nil && tags!.equals(topic.tags) {
            tags = nil
        }

        if pub == nil && priv == nil && tags == nil {
            // Unchanged
            _ = self.navigationController?.popViewController(animated: true)
            return
        }

        self.topic.setMeta(meta: MsgSetMeta(desc: pub != nil || priv != nil ? MetaSetDesc(pub: pub, priv: nil) : nil, tags: tags))
            .then(onSuccess: { _ in
                DispatchQueue.main.async {
                    _ = self.navigationController?.popViewController(animated: true)
                }
                return nil
            }, onFailure: UiUtils.ToastFailureHandler)
    }

    @objc
    func textFieldDidChange(_ textField: UITextField) {
        let text = textField.text ?? ""
        if Tinode.isValidTagValueFormat(tag: text) {
            textField.clearErrorSign()
            if !text.isEmpty {
                if let timer = aliasTesterTimer {
                    timer.invalidate()
                }
                aliasTesterTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkAliasValidity), userInfo: nil, repeats: false)
            }
        } else {
            textField.markAsError()
        }
    }

    @objc
    func manageTagsClicked(sender: UITapGestureRecognizer) {
        UiUtils.presentManageTagsEditDialog(over: self, forTopic: self.topic)
    }

    // This method is called for every keystroke, but validity is checked 1 second after the typing has stopped.
    @objc
    func checkAliasValidity() {
        guard let topic = self.topic, let alias = self.aliasTextField.text else {
            return
        }
        // Check if alias is already taken.
        guard let fnd = self.tinode?.getOrCreateFndTopic() else {
            // Unable to check: say "all is fine".
            return
        }

        // Check if alias is already taken.
        fnd.checkTagUniqueness(tag: "\(Tinode.kTagAlias)\(alias)", caller: topic.name)
            .thenApply { ok in
                DispatchQueue.main.async { [weak self] in
                    if ok ?? false {
                        self?.aliasTextField.clearErrorSign()
                    } else {
                        self?.aliasTextField.markAsError()
                    }
                }
                return nil
            }
            .thenCatch { err in
                DispatchQueue.main.async { [weak self] in
                    self?.aliasTextField.markAsError()
                }
                return nil
            }
    }
}

// UITableViewController
extension TopicGeneralViewController {
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let tt = self.topic else {
            return super.tableView(tableView, heightForRowAt: indexPath)
        }
        if indexPath.section == TopicGeneralViewController.kSectionBasic {
            // Hide empty uneditable rows.
            if (indexPath.row == TopicGeneralViewController.kSectionBasicAlias && !tt.isOwner && (tt.alias?.isEmpty ?? true)) ||
                (indexPath.row == TopicGeneralViewController.kSectionBasicPrivate && tt.isSlfType) ||
                (indexPath.row == TopicGeneralViewController.kSectionBasicDescription && !tt.isOwner && (tt.pub?.note?.isEmpty ?? true)) {
                return CGFloat.leastNonzeroMagnitude
            }
        } else if indexPath.section == TopicGeneralViewController.kSectionActions {
            if indexPath.row == TopicGeneralViewController.kSectionActionsManageTags && (!tt.isGrpType || !tt.isOwner) {
                // P2P topic has no owner, hide [Manage Tags]
                return CGFloat.leastNonzeroMagnitude
            }
        }

        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // Hide empty header in the first section.
        if section == TopicGeneralViewController.kSectionBasic {
            return CGFloat.leastNormalMagnitude
        }

        return super.tableView(tableView, heightForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        return 0
    }
}

extension TopicGeneralViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return UIModalPresentationStyle.none
    }
}

extension TopicGeneralViewController: ImagePickerDelegate {
    func didSelect(media: ImagePickerMediaType?) {
        guard case .image(let image, _, _) = media else { return }
        UiUtils.updateAvatar(forTopic: self.topic, image: image)
            .thenApply {_ in
                DispatchQueue.main.async { self.reloadData() }
                return nil
            }
    }
}

extension TopicGeneralViewController: UITextFieldDelegate {
    func textFieldDidEndEditing(_ textField: UITextField) {
        print("textFieldDidEndEditing \(textField.text ?? "")")
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let newLength = (textField.text ?? "").count + (string.count - range.length)
        if textField.tag == TopicGeneralViewController.kSectionBasicAlias {
            // Alias length.
            return newLength <= UiUtils.kMaxAliasLength
        }
        // Limit max length of the non-alias input.
        return newLength <= UiUtils.kMaxTitleLength
    }
}

extension TopicGeneralViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == .placeholderText {
            textView.text = nil
            textView.textColor = .secondaryLabel
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            textView.text = TopicGeneralViewController.kDescriptionPlaceholder
            textView.textColor = .placeholderText
        }
    }

    // Limit max length of the input.
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        return textView.text.count + (text.count - range.length) <= UiUtils.kMaxTopicDescriptionLength
    }
}
