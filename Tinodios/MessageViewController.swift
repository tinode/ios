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
    // Color of "read" marker.
    static let kDeliveryMarkerTint = UIColor(red: 19/255, green: 144/255, blue:255/255, alpha: 0.8)
    // Color of all other markers.
    static let kDeliveryMarkerColor = UIColor.gray.withAlphaComponent(0.7)
    // Light gray color
    static let kOutgoingBubbleColor = UIColor(red: 230/255, green: 230/255, blue: 230/255, alpha: 1)
    // Bright green color
    static let kIncomingBubbleColor = UIColor(red: 69/255, green: 193/255, blue: 89/255, alpha: 1)
    static let kContentFont = UIFont.preferredFont(forTextStyle: .body)
    static let kSenderNameFont = UIFont.preferredFont(forTextStyle: .caption2)
    static let kSenderNameLabelHeight: CGFloat = 16
    static let kNewDateFont = UIFont.boldSystemFont(ofSize: 10)
    static let kNewDateLabelHeight: CGFloat = 24
    static let kVerticalCellSpacing: CGFloat = 2
    static let kMinimumCellWidth:CGFloat = 60

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

        collectionView.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
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

        messageInputBar.delegate = self

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

// Methods for updating title area and refreshing messages.
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

// Methods for filling message with content and layout out message subviews.
extension MessageViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return messages.count
    }

    // Configure message cell for the given index: fill data and lay out subviews.
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: MessageCell.self), for: indexPath) as! MessageCell

        // To capture taps.
        cell.delegate = self

        // Cell content
        let message = messages[indexPath.item]

        // Set colors and fill out content except for avatar.
        configureCell(cell: cell, with: message, at: indexPath)

        // The message set has avatars.
        let hasAvatars = avatarsVisible(message: message)
        // This message has an avatar.
        let isAvatarVisible = shouldShowAvatar(for: message, at: indexPath)

        // Get cell frame and bounds.
        let attributes = collectionView.layoutAttributesForItem(at: indexPath)

        // Height of the field with the current date above the first message of the day.
        let newDateLabelHeight = isNewDateLabelVisible(at: indexPath) ? MessageViewController.kNewDateLabelHeight : 0
        // This is the height of the field with the sender's name.
        let senderNameLabelHeight = isAvatarVisible ? MessageViewController.kSenderNameLabelHeight : 0

        if isAvatarVisible {
            cell.avatarView.frame = CGRect(origin: CGPoint(x: 0, y: attributes!.frame.height - MessageViewController.kAvatarSize - senderNameLabelHeight), size: CGSize(width: MessageViewController.kAvatarSize, height: MessageViewController.kAvatarSize))

            // The avatar image should be assigned after setting the size. Otherwise it may be drawn twice.
            if let sub = topic?.getSubscription(for: message.from) {
                cell.avatarView.set(icon: sub.pub?.photo?.image(), title: sub.pub?.fn, id: message.from)
            } else {
                cell.avatarView.set(icon: nil, title: nil, id: message.from)
                print("Subscription not found for \(message.from ?? "nil")")
            }
        } else {
            cell.avatarView.frame = .zero
        }

        // Left padding in group topics with avatar
        let avatarPadding = hasAvatars ? MessageViewController.kAvatarSize : 0

        // Message content container (message bubble).
        let containerPadding = isFromCurrentSender(message: message) ?
            UIEdgeInsets(top: 0, left: 30, bottom: 0, right: 4) : UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 30)
        let containerSize = calcContainerSize(for: message, avatarsVisible: hasAvatars)
        // isFromCurrent Sender ? Flush container right : flush left.
        let originX = isFromCurrentSender(message: message) ? attributes!.frame.width - avatarPadding - containerSize.width - containerPadding.right : avatarPadding + containerPadding.left
        cell.containerView.frame = CGRect(origin: CGPoint(x: originX, y: newDateLabelHeight + containerPadding.top), size: containerSize)

        // Content UILabel.
        cell.content.textInsets = isFromCurrentSender(message: message) ? UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 18) : UIEdgeInsets(top: 7, left: 18, bottom: 7, right: 14)
        cell.content.font = MessageViewController.kContentFont
        cell.content.frame = cell.containerView.bounds

        // New date label
        if newDateLabelHeight > 0 {
            cell.newDateLabel.frame = CGRect(origin: CGPoint(x: 0, y: cell.containerView.frame.minY - containerPadding.top - newDateLabelHeight), size: CGSize(width: attributes!.frame.width, height: newDateLabelHeight))
        } else {
            cell.newDateLabel.frame = .zero
        }

        // Sender name under the avatar.
        if isAvatarVisible {
            cell.senderNameLabel.frame = CGRect(origin: CGPoint(x: 0, y: cell.containerView.frame.maxY + containerPadding.bottom), size: CGSize(width: attributes!.frame.width, height: senderNameLabelHeight))
        } else {
            cell.senderNameLabel.frame = .zero
        }

        // Draw the bubble
        bubbleDecorator(for: message, at: indexPath)(cell.containerView)

        return cell
    }

    private func configureCell(cell: MessageCell, with message: Message, at indexPath: IndexPath) {

        if isFromCurrentSender(message: message) {
            cell.containerView.backgroundColor = MessageViewController.kOutgoingBubbleColor
            cell.content.textColor = .darkText
        } else {
            cell.containerView.backgroundColor = MessageViewController.kIncomingBubbleColor
            cell.content.textColor = .white
        }

        cell.content.text = message.content?.string

        cell.newDateLabel.attributedText = newDateLabel(for: message, at: indexPath)
        cell.senderNameLabel.attributedText = senderFullName(for: message, at: indexPath)
    }

    func newDateLabel(for message: Message, at indexPath: IndexPath) -> NSAttributedString? {
        if isNewDateLabelVisible(at: indexPath) {
            return NSAttributedString(string: RelativeDateFormatter.shared.dateOnly(from: message.ts), attributes: [NSAttributedString.Key.font: MessageViewController.kNewDateFont, NSAttributedString.Key.foregroundColor: UIColor.darkGray])
        }
        return nil
    }

    // Get sender name
    func senderFullName(for message: Message, at indexPath: IndexPath) -> NSAttributedString? {
        guard shouldShowAvatar(for: message, at: indexPath) else { return nil }

        var senderName: String?
        if let sub = topic?.getSubscription(for: message.from), let pub = sub.pub {
            senderName = pub.fn
        }
        senderName = senderName ?? "Unknown \(message.from ?? "none")"

        return NSAttributedString(string: senderName!, attributes: [
            NSAttributedString.Key.font: MessageViewController.kSenderNameFont,
            NSAttributedString.Key.foregroundColor: UIColor.gray
            ])
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

    // Returns closure which draws message bubble in the supplied UIView.
    func bubbleDecorator(for message: Message, at indexPath: IndexPath) -> (UIView) -> Void {
        // FIXME: add tail to last message in sequence.
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
            if !isNextMessageSameSender(at: indexPath) || !isNextMessageSameDate(at: indexPath) {
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

// Helper methods for displaying message content
extension MessageViewController {
    // MARK: helper methods for displaying message content.

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

    func isFromCurrentSender(message: Message) -> Bool {
        return message.from == myUID
    }

    // Should avatars be shown at all for any message?
    func avatarsVisible(message: Message) -> Bool {
        return topic!.isGrpType && !isFromCurrentSender(message: message)
    }

    // Show avatar in the given message
    func shouldShowAvatar(for message: Message, at indexPath: IndexPath) -> Bool {
        return avatarsVisible(message: message) && (!isNextMessageSameSender(at: indexPath) || !isNextMessageSameDate(at: indexPath))
    }

    func isNewDateLabelVisible(at indexPath: IndexPath) -> Bool {
        return !isPreviousMessageSameDate(at: indexPath)
    }
}

// Message size calculation
extension MessageViewController: UICollectionViewDelegateFlowLayout {

    // Entry point for cell size calculations.
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {

        let height = cellHeightFromContent(for: messages[indexPath.item], at: indexPath)
        return CGSize(width: collectionView.bounds.size.width, height: CGFloat(height))
    }

    // Vertical spacing between message cells
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return MessageViewController.kVerticalCellSpacing
    }

    func cellHeightFromContent(for message: Message, at indexPath: IndexPath) -> CGFloat {
        let hasAvatars = avatarsVisible(message: message)

        let containerHeight = calcContainerSize(for: message, avatarsVisible: hasAvatars).height
        let senderNameLabelHeight: CGFloat = shouldShowAvatar(for: message, at: indexPath) ? 16 : 0
        let newDateLabelHeight: CGFloat = isNewDateLabelVisible(at: indexPath) ? 24 : 0
        let avatarHeight = hasAvatars ? MessageViewController.kAvatarSize : 0

        let totalLabelHeight: CGFloat = newDateLabelHeight + containerHeight + senderNameLabelHeight
        return max(avatarHeight, totalLabelHeight)
    }

    // Size of rectangle taken by the message content as attributedText.
    func textSize(for attributedText: NSAttributedString, considering maxWidth: CGFloat) -> CGSize {
        return attributedText.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).integral.size
    }

    // Calculate size of the view which holds message content.
    func calcContainerSize(for message: Message, avatarsVisible: Bool) -> CGSize {
        // FIXME: these calculations can be simplified, particularly no need to check isFromCurrentSender

        let insets = isFromCurrentSender(message: message) ? UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 18) : UIEdgeInsets(top: 7, left: 18, bottom: 7, right: 14)

        let avatarWidth = avatarsVisible ? MessageViewController.kAvatarSize : 0

        let padding = isFromCurrentSender(message: message) ? UIEdgeInsets(top: 0, left: 30, bottom: 0, right: 4) : UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 30)
        let maxWidth = collectionView.frame.width - avatarWidth - padding.left - padding.right - insets.left - insets.right

        let text = message.content?.string ?? "none"
        let attributedText = NSAttributedString(string: text, attributes: [.font: MessageViewController.kContentFont])
        var size = textSize(for: attributedText, considering: maxWidth)

        size.width += insets.left + insets.right
        size.width = max(size.width, MessageViewController.kMinimumCellWidth)
        size.height += insets.top + insets.bottom

        return size
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
