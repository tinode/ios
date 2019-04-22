//
//  MessageViewController.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit
import MessageKit
import MessageInputBar
import TinodeSDK

protocol MessageDisplayLogic: class {
    func updateTitleBar(icon: UIImage?, title: String?)
    func displayChatMessages(messages: [StoredMessage])
    func endRefresh()
}

class MessageViewController: MessageKit.MessagesViewController, MessageDisplayLogic {
    static let kOutgoingAvatarOverlap: CGFloat = 17.5

    var topicName: String? {
        didSet {
            topicType = Tinode.topicTypeByName(name: self.topicName)
            // Needed in order to get sender's avatar and display name
            topic = Cache.getTinode().getTopic(topicName: topicName!) as? DefaultComTopic
        }
    }
    var topicType: TopicType?
    var myUID: String?
    var topic: DefaultComTopic?

    var messages: [MessageType] = []

    private var interactor: (MessageBusinessLogic & MessageDataStore)?
    private let refreshControl = UIRefreshControl()
    private var noteTimer: Timer? = nil

    init() {
        super.init(nibName: nil, bundle: nil)
        self.setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setup()
    }

    private func setup() {
        myUID = Cache.getTinode().myUid

        let interactor = MessageInteractor()
        let presenter = MessagePresenter()
        interactor.presenter = presenter
        presenter.viewController = self

        self.interactor = interactor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        messagesCollectionView.messagesDataSource = self
        messageInputBar.delegate = self

        reloadInputViews()
        scrollsToBottomOnKeyboardBeginsEditing = true
        maintainPositionOnKeyboardFrameChanged = true

        messagesCollectionView.addSubview(refreshControl)
        refreshControl.addTarget(self, action: #selector(loadNextPage), for: .valueChanged)

        if let layout = messagesCollectionView.collectionViewLayout as? MessagesCollectionViewFlowLayout {
            layout.sectionInset = UIEdgeInsets(top: 1, left: 8, bottom: 1, right: 8)

            // Hide the outgoing avatar and adjust the label alignment to line up with the messages
            layout.setMessageOutgoingAvatarSize(.zero)
            layout.setMessageOutgoingMessageTopLabelAlignment(LabelAlignment(textAlignment: .right, textInsets: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)))
            layout.setMessageOutgoingMessageBottomLabelAlignment(LabelAlignment(textAlignment: .right, textInsets: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)))

            // Set incoming avatar to overlap with the message bubble
            layout.setMessageIncomingMessageTopLabelAlignment(LabelAlignment(textAlignment: .left, textInsets: UIEdgeInsets(top: 0, left: 18, bottom: MessageViewController.kOutgoingAvatarOverlap, right: 0)))

            if topic!.isP2PType {
                layout.setMessageIncomingAvatarSize(.zero)
            } else {
                layout.setMessageIncomingAvatarSize(CGSize(width: 30, height: 30))
                layout.setMessageIncomingMessagePadding(UIEdgeInsets(top: -MessageViewController.kOutgoingAvatarOverlap, left: -18, bottom: MessageViewController.kOutgoingAvatarOverlap, right: 18))
            }

            layout.setMessageIncomingAccessoryViewSize(CGSize(width: 30, height: 30))
            layout.setMessageIncomingAccessoryViewPadding(HorizontalEdgeInsets(left: 8, right: 0))
            layout.setMessageOutgoingAccessoryViewSize(CGSize(width: 30, height: 30))
            layout.setMessageOutgoingAccessoryViewPadding(HorizontalEdgeInsets(left: 0, right: 8))
        }

        messagesCollectionView.messagesLayoutDelegate = self
        messagesCollectionView.messagesDisplayDelegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        if !(self.interactor?.setup(topicName: self.topicName) ?? false) {
            print("error in interactor setup for \(String(describing: self.topicName))")
        }
        self.interactor?.attachToTopic()
        self.interactor?.loadMessages()
        self.noteTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true,
            block: { _ in
                self.interactor?.sendReadNotification()
            })
    }
    override func viewDidDisappear(_ animated: Bool) {
        self.interactor?.cleanup()
        self.noteTimer?.invalidate()
    }

    @objc func loadNextPage() {
        self.interactor?.loadNextPage()
    }

    func isNextMessageSameSender(at indexPath: IndexPath) -> Bool {
        guard indexPath.section + 1 < messages.count else { return false }
        return messages[indexPath.section].sender == messages[indexPath.section + 1].sender
    }
}

extension StoredMessage: MessageType {
    var sender: Sender {
        get {
            return Sender(
                id: self.from ?? "?",
                displayName: "dn-" + (self.from ?? "?"))
        }
    }
    var messageId: String {
        get { return self.id ?? "?" }
    }
    var sentDate: Date {
        get { return self.ts ?? Date() }
    }
    var kind: MessageKind {
        get { return .text(self.content ?? "") }
    }
}

extension MessageViewController {
    func updateTitleBar(icon: UIImage?, title: String?) {
        self.navigationItem.title = title ?? "Undefined"

        let avatarView = AvatarView()
        NSLayoutConstraint.activate([
                avatarView.heightAnchor.constraint(equalToConstant: 32),
                avatarView.widthAnchor.constraint(equalTo: avatarView.heightAnchor)
            ])
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: avatarView)
        avatarView.set(icon: icon, title: title, id: topicName)
   }

    func displayChatMessages(messages: [StoredMessage]) {
        self.messages = messages.reversed()
        self.messagesCollectionView.reloadData()
        self.messagesCollectionView.scrollToBottom()
    }

    func endRefresh() {
        DispatchQueue.main.async {
            self.refreshControl.endRefreshing()
        }
    }
}

extension MessageViewController: MessagesDataSource {
    func currentSender() -> Sender {
        return Sender(id: myUID ?? "???", displayName: "??")
    }
    func numberOfSections(in messagesCollectionView: MessagesCollectionView) -> Int {
        return messages.count
    }
    func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
        return messages[indexPath.section]
    }
    func isTimeLabelVisible(at indexPath: IndexPath) -> Bool {
        return true//indexPath.section % 3 == 0 && !isPreviousMessageSameSender(at: indexPath)
    }
    func messageTopLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        guard topic!.isGrpType && !isFromCurrentSender(message: message) else { return nil }

        let name = message.sender.displayName
        return NSAttributedString(string: name, attributes: [
            NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .caption1),
            NSAttributedString.Key.foregroundColor: UIColor.gray
            ])
    }
    func messageBottomLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        let dateString = message.sentDate.formatRelative()
        return NSAttributedString(string: dateString, attributes: [
            NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .caption2),
            NSAttributedString.Key.foregroundColor: UIColor.gray
            ])
    }
}

extension MessageViewController: MessagesDisplayDelegate, MessagesLayoutDelegate {

    func configureAvatarView(_ avatarView: AvatarView, for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        // Hide current user's avatar as well as peer's avatar in p2p topics.
        // Avatars are useful in group topics only
        if topic!.isP2PType || isNextMessageSameSender(at: indexPath) {
            avatarView.isHidden = true
            return
        }

        let sub = topic?.getSubscription(for: message.sender.id)
        avatarView.set(icon: sub?.pub?.photo?.image(), title: sub?.pub?.fn, id: message.sender.id)
        if sub == nil {
            print("subscription not found for \(message.sender.id)")
        }
    }

    func textColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return !isFromCurrentSender(message: message) ? .white : .darkText
    }
    func backgroundColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return !isFromCurrentSender(message: message)
            ? UIColor(red: 69/255, green: 193/255, blue: 89/255, alpha: 1)
            : UIColor(red: 230/255, green: 230/255, blue: 230/255, alpha: 1)
    }
    func cellTopLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return 8
    }
    func messageTopLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return topic!.isGrpType || isFromCurrentSender(message: message) ? 0 : 16
    }
    func messageBottomLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        return 16
    }
}

extension MessageViewController: MessageInputBarDelegate {
    func messageInputBar(_ inputBar: MessageInputBar, didPressSendButtonWith text: String) {
        _ = interactor?.sendMessage(content: text)
        messageInputBar.inputTextView.text.removeAll()
        messageInputBar.invalidatePlugins()
    }

    func messageInputBar(_ inputBar: MessageInputBar, textViewTextDidChangeTo text: String) {
        // Use to send a typing indicator
    }

    func messageInputBar(_ inputBar: MessageInputBar, didChangeIntrinsicContentTo size: CGSize) {
        // Use to change any other subview insets
    }
}
