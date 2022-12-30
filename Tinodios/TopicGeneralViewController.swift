//
//  TopicGeneralViewController.swift
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

class TopicGeneralViewController: UITableViewController {

    private static let kSectionBasic = 0
    private static let kSectionBasicDescription = 2

    private static let kSectionActions = 1
    private static let kSectionActionsManageTags = 0

    var topicName = ""
    private var topic: DefaultComTopic!
    private var tinode: Tinode!
    private var imagePicker: ImagePicker!

    @IBOutlet weak var actionManageTags: UITableViewCell!

    @IBOutlet weak var topicTitleLabel: UILabel!
    @IBOutlet weak var topicDescriptionLabel: UILabel!
    @IBOutlet weak var topicPrivateLabel: UILabel!

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

        UiUtils.setupTapRecognizer(
            forView: actionManageTags,
            action: #selector(TopicGeneralViewController.manageTagsClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: topicPrivateLabel,
            action: #selector(TopicGeneralViewController.topicPrivateTapped),
            actionTarget: self)
        if topic.isOwner {
            UiUtils.setupTapRecognizer(
                forView: topicTitleLabel,
                action: #selector(TopicGeneralViewController.topicTitleTapped),
                actionTarget: self)
            UiUtils.setupTapRecognizer(
                forView: topicDescriptionLabel,
                action: #selector(TopicGeneralViewController.topicDescriptionTapped),
                actionTarget: self)
        }
        self.imagePicker = ImagePicker(
            presentationController: self, delegate: self, editable: true)
    }

    private func reloadData() {
        topicTitleLabel.text = (topic.pub?.fn ?? "").isEmpty ? NSLocalizedString("Unknown", comment: "Placeholder for missing user name") : topic.pub?.fn

        let isEmpty = topic?.pub?.note?.isEmpty ?? true
        topicDescriptionLabel.textColor = isEmpty ? .placeholderText : .secondaryLabel
        if topic.isOwner || !isEmpty {
            topicDescriptionLabel.isHidden = false
            topicDescriptionLabel.text = isEmpty ? NSLocalizedString("Add optional description", comment: "Placeholder for missing topic description") : topic.pub?.note
        } else {
            topicDescriptionLabel.isHidden = true
        }

        topicPrivateLabel.textColor = topic?.comment?.isEmpty ?? true ? .placeholderText : .secondaryLabel
        topicPrivateLabel.text = (topic.comment ?? "").isEmpty ? NSLocalizedString("Private info: not set", comment: "Placeholder text in editor") : topic.comment

        avatarImage.set(pub: topic.pub, id: topic.name, deleted: topic.deleted)
        avatarImage.letterTileFont = self.avatarImage.letterTileFont.withSize(CGFloat(50))
    }

    @IBAction func loadAvatarClicked(_ sender: Any) {
        imagePicker.present(from: self.view)
    }

    @objc
    func topicTitleTapped(sender: UITapGestureRecognizer) {
        UiUtils.alertLabelEditor(over: self, self.topic?.pub?.fn, placeholder: NSLocalizedString("Name of the group", comment: "Alert placeholder"), title: NSLocalizedString("Edit Title", comment: "Alert title"), done: { text in
            if let nt = text, !nt.isEmpty {
                if let oldPub = self.topic.pub, oldPub.fn != nt {
                    let pub = TheCard(fn: String(nt.prefix(UiUtils.kMaxTitleLength)))
                    UiUtils.setTopicData(forTopic: self.topic, pub: pub, priv: nil).thenFinally {
                        DispatchQueue.main.async { self.reloadData() }
                    }
                }
            }
        })
    }

    @objc
    func topicDescriptionTapped(sender: UITapGestureRecognizer) {
        let alert = MultilineAlertViewController(with: self.topic?.pub?.note)
        alert.title = NSLocalizedString("Edit Description", comment: "Alert title")
        alert.completionHandler = { text in
            let pub = TheCard()
            if let nd = text, !nd.isEmpty {
                if let oldPub = self.topic.pub, oldPub.note != nd {
                    pub.note = String(nd.prefix(UiUtils.kMaxTitleLength))
                }
            } else {
                pub.note = Tinode.kNullValue
            }
            UiUtils.setTopicData(forTopic: self.topic, pub: pub, priv: nil).thenFinally {
                DispatchQueue.main.async { self.reloadData() }
            }
        }
        alert.show(over: self)
    }

    @objc
    func topicPrivateTapped(sender: UITapGestureRecognizer) {
        UiUtils.alertLabelEditor(over: self, self.topic?.comment, placeholder: NSLocalizedString("Additional info (private)", comment: "Alert placeholder"), title: NSLocalizedString("Private Comment", comment: "Alert title"), done: { text in
            var priv = PrivateType()
            if let ns = text, !ns.isEmpty {
                if self.topic.comment == nil || (self.topic.comment! != ns) {
                    priv.comment = String(ns.prefix(UiUtils.kMaxTitleLength))
                }
            } else {
                priv.comment = Tinode.kNullValue
            }
            UiUtils.setTopicData(forTopic: self.topic, pub: nil, priv: priv).thenFinally {
                DispatchQueue.main.async { self.reloadData() }
            }
        })
    }

    @objc func manageTagsClicked(sender: UITapGestureRecognizer) {
        UiUtils.presentManageTagsEditDialog(over: self, forTopic: self.topic)
    }

    private func promiseSuccessHandler(msg: ServerMessage?) throws -> PromisedReply<ServerMessage>? {
        DispatchQueue.main.async { self.reloadData() }
        return nil
    }
}

extension TopicGeneralViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return UIModalPresentationStyle.none
    }
}

extension TopicGeneralViewController {
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == TopicGeneralViewController.kSectionBasic {
            if indexPath.row == TopicGeneralViewController.kSectionBasicDescription && !(topic?.isOwner ?? false) && (topic?.pub?.note?.isEmpty ?? true) {
                // Hide impty uneditable Description row.
                return CGFloat.leastNonzeroMagnitude
            }
        } else if indexPath.section == TopicGeneralViewController.kSectionActions {
            if indexPath.row == TopicGeneralViewController.kSectionActionsManageTags && (!(topic?.isGrpType ?? false) || !(topic?.isOwner ?? false)) {
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

extension TopicGeneralViewController: ImagePickerDelegate {
    func didSelect(media: ImagePickerMediaType?) {
        guard case .image(let image, _, _) = media else { return }
        UiUtils.updateAvatar(forTopic: self.topic, image: image)
            .thenApply(self.promiseSuccessHandler)
    }
}
