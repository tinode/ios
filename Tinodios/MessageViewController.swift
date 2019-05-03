//
//  MessageViewController.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit
import MessageInputBar
import TinodeSDK

protocol MessageDisplayLogic: class {
    func updateTitleBar(icon: UIImage?, title: String?)
    func displayChatMessages(messages: [StoredMessage])
    func endRefresh()
}

class MessageViewController: UIViewController {

    // MARK: static parameters

    static let kAvatarSize: CGFloat = 30
    static let kDeliveryMarkerSize: CGFloat = 16
    static let kDeliveryMarkerTint = UIColor(red: 19/255, green: 144/255, blue:255/255, alpha: 0.8)
    static let kDeliveryMarkerColor = UIColor.gray.withAlphaComponent(0.7)
    static let kOutgoingBubbleColor = UIColor(red: 230/255, green: 230/255, blue: 230/255, alpha: 1)
    static let kIncomingBubbleColor = UIColor(red: 69/255, green: 193/255, blue: 89/255, alpha: 1)

    /// The `MessageInputBar` used as the `inputAccessoryView` in the view controller.
    private var messageInputBar = MessageInputBar()

    private weak var collectionView: MessageView!

    private var interactor: (MessageBusinessLogic & MessageDataStore)?
    private let refreshControl = UIRefreshControl()

    // MARK: properties

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

    private var noteTimer: Timer? = nil

    var messages: [Message] = []

    // MARK: initializers

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

    // MARK: lifecycle

    deinit {
        // removeKeyboardObservers()
        // removeMenuControllerObservers()
    }

    override func loadView() {
        super.loadView()

        let collectionView = MessageView()

        // Appearance and behavior.
        extendedLayoutIncludesOpaqueBars = true
        automaticallyAdjustsScrollViewInsets = false

        // Collection View setup
        collectionView.keyboardDismissMode = .interactive
        collectionView.alwaysBounceVertical = true
        view.addSubview(collectionView)
        self.collectionView = collectionView

        collectionView.addSubview(refreshControl)
        refreshControl.addTarget(self, action: #selector(loadNextPage), for: .valueChanged)

        // Setup UICollectionView constraints: fill the screen
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        let top = collectionView.topAnchor.constraint(equalTo: view.topAnchor, constant: topLayoutGuide.length)
        let bottom = collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        let trailing: NSLayoutConstraint, leading: NSLayoutConstraint
        if #available(iOS 11.0, *) {
            leading = collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
            trailing = collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        } else {
            leading = collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            trailing = collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        }
        NSLayoutConstraint.activate([top, bottom, trailing, leading])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white

        collectionView.delegate = self
        collectionView.dataSource = self

        // addMenuControllerObservers()

        // messageInputBar.delegate = self

        reloadInputViews()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

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
        super.viewDidDisappear(animated)

        self.interactor?.cleanup()
        self.noteTimer?.invalidate()
    }

    @objc func loadNextPage() {
        self.interactor?.loadNextPage()
    }
}

extension MessageViewController: MessageDisplayLogic {

    func updateTitleBar(icon: UIImage?, title: String?) {
        self.navigationItem.title = title ?? "Undefined"

        let avatarView = RoundImageView(icon: icon, title: title, id: topicName)
        NSLayoutConstraint.activate([
                avatarView.heightAnchor.constraint(equalToConstant: 32),
                avatarView.widthAnchor.constraint(equalTo: avatarView.heightAnchor)
            ])
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: avatarView)
   }

    func displayChatMessages(messages: [StoredMessage]) {
        self.messages = messages.reversed()
        self.collectionView.reloadData()
        // FIXME: don't scroll to bottom in response to loading the next page.
        // Maybe don't scroll to bottom if the view is not at the bottom already.
        self.collectionView.scrollToBottom()
    }

    func endRefresh() {
        DispatchQueue.main.async {
            self.refreshControl.endRefreshing()
        }
    }
}

// Helper methods for data handling
extension MessageViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return messages.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let message = messages[indexPath.item]
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: MessageCell.self), for: indexPath) as! MessageCell
        configureCell(cell: cell, with: message, at: indexPath)
        return cell
    }

    func configureCell(cell: MessageCell, with message: Message, at indexPath: IndexPath) {

        cell.delegate = self

        cell.avatarView = avatarView(for: message, at: indexPath)

        cell.containerView.backgroundColor = backgroundColor(for: message, at: indexPath)
        bubbleDecorator(for: message, at: indexPath)(cell.containerView)

        cell.newDateLabel.attributedText = newDateLabel(for: message, at: indexPath)
        cell.senderNameLabel.attributedText = senderFullName(for: message, at: indexPath)
    }

    func isFromCurrentSender(message: Message) -> Bool {
        return message.from == myUID
    }

    func shouldShowAvatar(message: Message, at indexPath: IndexPath) -> Bool {
        return topic!.isGrpType && !isFromCurrentSender(message: message) && (!isNextMessageSameSender(at: indexPath) || !isNextMessageSameDate(at: indexPath))
    }

    func isNewDateLabelVisible(at indexPath: IndexPath) -> Bool {
        return !isPreviousMessageSameDate(at: indexPath)
    }

    func newDateLabel(for message: Message, at indexPath: IndexPath) -> NSAttributedString? {
        if isNewDateLabelVisible(at: indexPath) {
            return NSAttributedString(string: RelativeDateFormatter.shared.dateOnly(from: message.ts), attributes: [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 10), NSAttributedString.Key.foregroundColor: UIColor.darkGray])
        }
        return nil
    }

    func senderFullName(for message: Message, at indexPath: IndexPath) -> NSAttributedString? {
        guard shouldShowAvatar(message: message, at: indexPath) else { return nil }

        var senderName: String?
        if let sub = topic?.getSubscription(for: message.from), let pub = sub.pub {
            senderName = pub.fn
        }
        senderName = senderName ?? "Unknown \(message.from ?? "none")"

        return NSAttributedString(string: senderName!, attributes: [
            NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .caption2),
            NSAttributedString.Key.foregroundColor: UIColor.gray
            ])
    }
}

// Helper methods for displaying message content
extension MessageViewController {
    // Helper checks.

    func isPreviousMessageSameDate(at indexPath: IndexPath) -> Bool {
        guard indexPath.item > 0 else { return false }
        guard let this = messages[indexPath.item].ts, let prev = messages[indexPath.item - 1].ts else { return false }
        return Calendar.current.isDate(this, inSameDayAs: prev)
    }

    func isNextMessageSameDate(at indexPath: IndexPath) -> Bool {
        guard indexPath.item + 1 < messages.count else { return false }
        guard let this = messages[indexPath.item].ts, let next = messages[indexPath.item + 1].ts else { return false }
        return Calendar.current.isDate(this, inSameDayAs: next)
    }

    func isPreviousMessageSameSender(at indexPath: IndexPath) -> Bool {
        guard indexPath.item > 0 else { return false }
        return messages[indexPath.item].from == messages[indexPath.item - 1].from
    }

    func isNextMessageSameSender(at indexPath: IndexPath) -> Bool {
        guard indexPath.item + 1 < messages.count else { return false }
        return messages[indexPath.item].from == messages[indexPath.item + 1].from
    }

    func deliveryMarker(for message: Message, at indexPath: IndexPath) -> UIImageView? {
        guard isFromCurrentSender(message: message), let topic = topic else { return nil }

        let iconName: String
        var tint: UIColor = MessageViewController.kDeliveryMarkerColor
        if message.isPending {
            iconName = "outline_schedule_white_48pt"
        } else {
            if topic.msgReadCount(seq: message.seqId) > 0 {
                iconName = "outline_done_all_white_48pt"
                tint = MessageViewController.kDeliveryMarkerTint
            } else if topic.msgRecvCount(seq: message.seqId) > 0 {
                iconName = "outline_done_all_white_48pt"
            } else {
                iconName = "outline_done_white_48pt"
            }
        }

        let marker = UIImageView(image: UIImage(named: iconName))
        marker.tintColor = tint
        
        return marker
    }

    func avatarView(for message: Message, at indexPath: IndexPath) -> UIImageView {
        guard shouldShowAvatar(message: message, at: indexPath) else { return UIImageView() }

        if let sub = topic?.getSubscription(for: message.from) {
            return RoundImageView(icon: sub.pub?.photo?.image(), title: sub.pub?.fn, id: message.from)
        }

        print("Subscription not found for \(message.from ?? "nil")")

        return UIImageView()
    }

    func textColor(for message: Message, at indexPath: IndexPath) -> UIColor {
        return !isFromCurrentSender(message: message) ? .white : .darkText
    }

    func backgroundColor(for message: Message, at indexPath: IndexPath) -> UIColor {
        return !isFromCurrentSender(message: message) ? MessageViewController.kIncomingBubbleColor : MessageViewController.kOutgoingBubbleColor
    }

    // Returns function which draws message bubble.
    func bubbleDecorator(for message: Message, at indexPath: IndexPath) -> (UIView) -> Void {
        var corners: UIRectCorner = []

        if isFromCurrentSender(message: message) {
            corners.formUnion(.topLeft)
            corners.formUnion(.bottomLeft)
            if !isPreviousMessageSameSender(at: indexPath) || !isPreviousMessageSameDate(at: indexPath) {
                corners.formUnion(.topRight)
            }
            if !isNextMessageSameSender(at: indexPath) || !isNextMessageSameDate(at: indexPath) {
                corners.formUnion(.bottomRight)
            }
        } else {
            corners.formUnion(.topRight)
            corners.formUnion(.bottomRight)
            if !isPreviousMessageSameSender(at: indexPath) || !isPreviousMessageSameDate(at: indexPath) {
                corners.formUnion(.topLeft)
            }
            if !isNextMessageSameSender(at: indexPath) || !isNextMessageSameSender(at: indexPath) {
                corners.formUnion(.bottomLeft)
            }
        }

        return { view in
            let radius: CGFloat = 16
            let path = UIBezierPath(roundedRect: view.bounds, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
            let mask = CAShapeLayer()
            mask.path = path.cgPath
            view.layer.mask = mask
        }
    }
}

// Message size calculation
extension MessageViewController: UICollectionViewDelegateFlowLayout {

    // Hight of the label above the first message in the day
    func newDateLabelHeight(for message: Message, at indexPath: IndexPath) -> CGFloat {
        if isNewDateLabelVisible(at: indexPath) {
            return 24
        }
        return 0
    }

    // This is the hight of the field with the sender's name.
    func senderNameLabelHeight(for message: Message, at indexPath: IndexPath) -> CGFloat {
        return isFromCurrentSender(message: message) || (isNextMessageSameSender(at: indexPath) && isNextMessageSameDate(at: indexPath)) ? 0 : 16
    }
}

extension MessageViewController: MessageCellDelegate {
    func didTapMessage(in cell: MessageCell) {
        print("didTapMessage")
    }

    func didTapAvatar(in cell: MessageCell) {
        print("didTapAvatar")
    }
}

extension MessageViewController: MessageInputBarDelegate {
    func messageInputBar(_ inputBar: MessageInputBar, didPressSendButtonWith text: String) {
        _ = interactor?.sendMessage(content: Drafty(content: text))
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


