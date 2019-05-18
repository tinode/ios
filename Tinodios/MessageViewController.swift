//
//  MessageViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

protocol MessageDisplayLogic: class {
    func updateTitleBar(icon: UIImage?, title: String?)
    func displayChatMessages(messages: [StoredMessage])
    func endRefresh()
}

class MessageViewController: UIViewController {

    // MARK: static parameters

    private enum Constants {
        /// Size of the avatar in the nav bar in small state.
        static let kNavBarAvatarSmallState: CGFloat = 32

        /// Size of the avatar in group topics.
        static let kAvatarSize: CGFloat = 30

        // Size of delivery marker (checkmarks etc)
        static let kDeliveryMarkerSize: CGFloat = 16
        // Color of "read" delivery marker.
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
        // Vertical spacing between messages from the same user
        static let kVerticalCellSpacing: CGFloat = 2
        // Additional vertical spacing between messages from different users in P2P topics.
        static let kAdditionalP2PVerticalCellSpacing: CGFloat = 4
        static let kMinimumCellWidth: CGFloat = 60
        // This is the space between the other side of the message and the edge of screen.
        // I.e. for incoming messages the space between the message and the *right* edge, for
        // outfoing between the message and the left edge.
        static let kFarSideHorizontalSpacing: CGFloat = 45

        // Insets around collection view, i.e. main view padding
        static let kCollectionViewInset = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

        // Insets for the message bubble relative to collectionView: bubble should not touch the sides of the screen.
        static let kIncomingContainerPadding = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: Constants.kFarSideHorizontalSpacing)
        static let kOutgoingContainerPadding = UIEdgeInsets(top: 0, left: Constants.kFarSideHorizontalSpacing, bottom: 0, right: 0)

        // Insets around content inside the message bubble.
        static let kIncomingMessageContentInset = UIEdgeInsets(top: 7, left: 18, bottom: 7, right: 14)
        static let kOutgoingMessageContentInset = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 18)
    }

    /// The `sendMessageBar` is used as the `inputAccessoryView` in the view controller.
    private lazy var sendMessageBar: SendMessageBar = {
        let view = SendMessageBar()
        view.autoresizingMask = .flexibleHeight
        return view
    }()

    /// Avatar in the NavBar
    private lazy var navBarAvatarView: UIImageView = {
        return UIImageView()
    }()

    /// Pointer to the view holding messages.
    weak var collectionView: MessageView!

    private var interactor: (MessageBusinessLogic & MessageDataStore)?
    private let refreshControl = UIRefreshControl()

    // MARK: properties

    var topicName: String? {
        didSet {
            topicType = Tinode.topicTypeByName(name: self.topicName)
            // Needed in order to get sender's avatar and display name
            let tinode = Cache.getTinode()
            topic = tinode.getTopic(topicName: topicName!) as? DefaultComTopic
            if topic == nil {
                topic = tinode.newTopic(for: topicName!, with: nil) as? DefaultComTopic
            }
        }
    }
    var topicType: TopicType?
    var myUID: String?
    var topic: DefaultComTopic?

    private var noteTimer: Timer? = nil

    // Messages to be displayed
    var messages: [Message] = []
    // Cache of message cell sizes. Calculation of cell sizes is heavy. Caching the result to improve scrolling performance.
    var cellSizeCache: [CGSize?] = []

    var isInitialLayout = true

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
        removeKeyboardObservers()
        // removeMenuControllerObservers()
    }

    // This makes messageInputBar visible.
    override var inputAccessoryView: UIView? {
        return sendMessageBar
    }

    override var canBecomeFirstResponder: Bool {
        return true
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

        collectionView.layoutMargins = Constants.kCollectionViewInset

        collectionView.addSubview(refreshControl)
        refreshControl.addTarget(self, action: #selector(loadNextPage), for: .valueChanged)

        // Setup UICollectionView constraints: fill the screen
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        let top = collectionView.topAnchor.constraint(equalTo: view.topAnchor, constant: topLayoutGuide.length)
        let trailing: NSLayoutConstraint, leading: NSLayoutConstraint, bottom: NSLayoutConstraint
        if #available(iOS 11.0, *) {
            // Extra padding as -50. It's probably due to a bug somewhere.
            bottom = collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50)
            leading = collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
            trailing = collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        } else {
            bottom = collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            leading = collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            trailing = collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        }
        NSLayoutConstraint.activate([top, bottom, trailing, leading])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white

        self.collectionView.delegate = self
        self.collectionView.dataSource = self

        // addMenuControllerObservers()

        sendMessageBar.delegate = self
    }

    override func viewDidLayoutSubviews() {
        // Otherwise setting contentInset after viewDidAppear will be animated.
        if isInitialLayout {
            defer { isInitialLayout = false }
            addKeyboardObservers()
        }
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

        navBarAvatarView = RoundImageView(icon: icon, title: title, id: topicName)
        navBarAvatarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
                navBarAvatarView.heightAnchor.constraint(equalToConstant: Constants.kNavBarAvatarSmallState),
                navBarAvatarView.widthAnchor.constraint(equalTo: navBarAvatarView.heightAnchor)
            ])
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: navBarAvatarView)
   }

    func displayChatMessages(messages: [StoredMessage]) {
        self.messages = messages.reversed()
        self.cellSizeCache = Array(repeating: nil, count: messages.count)
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

        // The message set has avatars.
        let hasAvatars = avatarsVisible(message: message)
        // This message has an avatar.
        let isAvatarVisible = shouldShowAvatar(for: message, at: indexPath)

        // Insets for the message bubble relative to collectionView: bubble should not touch the sides of the screen.
        let containerPadding = isFromCurrentSender(message: message) ? Constants.kOutgoingContainerPadding : Constants.kIncomingContainerPadding

        // Maxumum allowed content width.
        let maxContentWidth = calcMaxContentWidth(for: message, avatarsVisible: hasAvatars)

        // Set colors and fill out content except for the avatar. The maxumum size is needed for placing attached images.
        configureCell(cell: cell, with: message, at: indexPath, maxSize: CGSize(width: maxContentWidth, height: collectionView.frame.height * 0.66))

        // Now that the cell is filled with content, get cell frame and bounds.
        let cellSize = calcCellSize(forItemAt: indexPath)

        // Height of the field with the current date above the first message of the day.
        let newDateLabelHeight = calcNewDateLabelHeight(at: indexPath)

        // This is the height of the field with the sender's name.
        let senderNameLabelHeight = isAvatarVisible ? Constants.kSenderNameLabelHeight : 0

        if isAvatarVisible {
            cell.avatarView.frame = CGRect(origin: CGPoint(x: 0, y: cellSize.height - Constants.kAvatarSize - senderNameLabelHeight), size: CGSize(width: Constants.kAvatarSize, height: Constants.kAvatarSize))

            // The avatar image should be assigned after setting the size. Otherwise it may be drawn twice.
            if let sub = topic?.getSubscription(for: message.from) {
                cell.avatarView.set(icon: sub.pub?.photo?.image(), title: sub.pub?.fn, id: message.from)
            } else {
                cell.avatarView.set(icon: nil, title: nil, id: message.from)
                print("Subscription not found for \(message.from ?? "nil")")
            }

            // Sender name under the avatar.
            cell.senderNameLabel.frame = CGRect(origin: CGPoint(x: 0, y: cellSize.height - senderNameLabelHeight), size: CGSize(width: cellSize.width, height: senderNameLabelHeight))
        } else {
            cell.avatarView.frame = .zero
            cell.senderNameLabel.frame = .zero
        }

        // Additional left padding in group topics with avatar
        let avatarPadding = hasAvatars ? Constants.kAvatarSize : 0

        // FIXME: this call calculates content size for the second time.
        let containerSize = calcContainerSize(for: message, avatarsVisible: hasAvatars)
        // isFromCurrent Sender ? Flush container right : flush left.
        let originX = isFromCurrentSender(message: message) ? cellSize.width - avatarPadding - containerSize.width - containerPadding.right : avatarPadding + containerPadding.left
        cell.containerView.frame = CGRect(origin: CGPoint(x: originX, y: newDateLabelHeight + containerPadding.top), size: containerSize)

        // Content: RichTextLabel.
        let contentInset = isFromCurrentSender(message: message) ? Constants.kOutgoingMessageContentInset : Constants.kIncomingMessageContentInset
        cell.content.frame = cell.containerView.bounds.inset(by: contentInset)

        // New date label
        if newDateLabelHeight > 0 {
            cell.newDateLabel.frame = CGRect(origin: CGPoint(x: 0, y: cell.containerView.frame.minY - containerPadding.top - newDateLabelHeight), size: CGSize(width: cellSize.width, height: newDateLabelHeight))
        } else {
            cell.newDateLabel.frame = .zero
        }

        // Draw the bubble
        bubbleDecorator(for: message, at: indexPath)(cell.containerView)

        return cell
    }

    private func configureCell(cell: MessageCell, with message: Message, at indexPath: IndexPath, maxSize: CGSize) {

        cell.content.backgroundColor = nil
        if isFromCurrentSender(message: message) {
            cell.containerView.backgroundColor = Constants.kOutgoingBubbleColor
            cell.content.textColor = .darkText
        } else {
            cell.containerView.backgroundColor = Constants.kIncomingBubbleColor
            cell.content.textColor = .white
        }

        cell.content.font = Constants.kContentFont

        if let drafty = message.content {
            if drafty.isPlain {
                cell.content.text = drafty.string
            } else {
                cell.content.attributedText = AttribFormatter.toAttributed(drafty, maxSize: maxSize, defaultAttrs: [.font: Constants.kContentFont, .foregroundColor: cell.content.textColor!])
            }
        }

        cell.newDateLabel.attributedText = newDateLabel(for: message, at: indexPath)
        cell.senderNameLabel.attributedText = senderFullName(for: message, at: indexPath)
    }

    func newDateLabel(for message: Message, at indexPath: IndexPath) -> NSAttributedString? {
        if isNewDateLabelVisible(at: indexPath) {
            return NSAttributedString(string: RelativeDateFormatter.shared.dateOnly(from: message.ts), attributes: [NSAttributedString.Key.font: Constants.kNewDateFont, NSAttributedString.Key.foregroundColor: UIColor.darkGray])
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
            NSAttributedString.Key.font: Constants.kSenderNameFont,
            NSAttributedString.Key.foregroundColor: UIColor.gray
            ])
    }

    func deliveryMarker(for message: Message, at indexPath: IndexPath) -> UIImageView? {
        guard isFromCurrentSender(message: message), let topic = topic else { return nil }

        let iconName: String
        var tint: UIColor = Constants.kDeliveryMarkerColor
        if message.isPending {
            iconName = "outline_schedule_white_48pt"
        } else {
            if topic.msgReadCount(seq: message.seqId) > 0 {
                iconName = "outline_done_all_white_48pt"
                tint = Constants.kDeliveryMarkerTint
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
extension MessageViewController : UICollectionViewDelegateFlowLayout {

    // MARK: UICollectionViewDelegateFlowLayout methods

    // Entry point for cell size calculations.
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return calcCellSize(forItemAt: indexPath)
    }

    // Vertical spacing between message cells
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return Constants.kVerticalCellSpacing
    }

    // MARK: supporting methods

    // Calculate and cache message cell size
    func calcCellSize(forItemAt indexPath: IndexPath) -> CGSize {
        if let size = cellSizeCache[indexPath.item] {
            return size
        }

        let message = messages[indexPath.item]
        let hasAvatars = avatarsVisible(message: message)
        let containerHeight = calcContainerSize(for: message, avatarsVisible: hasAvatars).height
        let size = CGSize(width: calcCellWidth(), height: calcCellHeightFromContent(for: message, at: indexPath, containerHeight: containerHeight, avatarsVisible: hasAvatars))
        cellSizeCache[indexPath.item] = size
        return size
    }

    func calcCellWidth() ->CGFloat {
        return collectionView.frame.width - collectionView.layoutMargins.left - collectionView.layoutMargins.right
    }

    func calcCellHeightFromContent(for message: Message, at indexPath: IndexPath, containerHeight: CGFloat, avatarsVisible hasAvatars: Bool) -> CGFloat {

        let senderNameLabelHeight: CGFloat = shouldShowAvatar(for: message, at: indexPath) ? Constants.kSenderNameLabelHeight : 0
        let newDateLabelHeight: CGFloat = calcNewDateLabelHeight(at: indexPath)
        let avatarHeight = hasAvatars ? Constants.kAvatarSize : 0

        let totalLabelHeight: CGFloat = newDateLabelHeight + containerHeight + senderNameLabelHeight
        return max(avatarHeight, totalLabelHeight)
    }

    func calcNewDateLabelHeight(at indexPath: IndexPath) -> CGFloat {
        let height: CGFloat
        if isNewDateLabelVisible(at: indexPath) {
            height = Constants.kNewDateLabelHeight
        } else if !topic!.isGrpType && !isPreviousMessageSameSender(at: indexPath) {
            height = Constants.kAdditionalP2PVerticalCellSpacing
        } else {
            height = 0
        }
        return height
    }

    // Calculate maximum width of content inside message bubble
    func calcMaxContentWidth(for message: Message, avatarsVisible: Bool) -> CGFloat {

        let insets = isFromCurrentSender(message: message) ? Constants.kOutgoingMessageContentInset : Constants.kIncomingMessageContentInset

        let avatarWidth = avatarsVisible ? Constants.kAvatarSize : 0

        let padding = isFromCurrentSender(message: message) ? Constants.kOutgoingContainerPadding : Constants.kIncomingContainerPadding

        return calcCellWidth() - avatarWidth - padding.left - padding.right - insets.left - insets.right
    }

    /// Calculate size of the view which holds message content.
    func calcContainerSize(for message: Message, avatarsVisible: Bool) -> CGSize {
        let maxWidth = calcMaxContentWidth(for: message, avatarsVisible: avatarsVisible)
        let insets = isFromCurrentSender(message: message) ? Constants.kOutgoingMessageContentInset : Constants.kIncomingMessageContentInset

        var size = calcContentSize(for: message, maxWidth: maxWidth)

        size.width += insets.left + insets.right
        size.width = max(size.width, Constants.kMinimumCellWidth)
        size.height += insets.top + insets.bottom

        return size
    }

    /// Calculate size of message content.
    func calcContentSize(for message: Message, maxWidth: CGFloat) -> CGSize {
        let attributedText: NSAttributedString

        if let drafty = message.content {
            attributedText = AttribFormatter.toAttributed(drafty, maxSize: CGSize(width: maxWidth, height: collectionView.frame.height * 0.66), defaultAttrs: [.font: Constants.kContentFont])
        } else {
            attributedText = NSAttributedString(string: "none", attributes: [.font: Constants.kContentFont])
        }

        let size = attributedText.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).integral.size
        return size
    }
}

// Methods for handling taps in messages.

extension MessageViewController : MessageCellDelegate {
    func didTapContent(in cell: MessageCell, url: URL?) {
        print("didTapContent URL=\(url?.absoluteString ?? "nil")")
    }

    func didTapMessage(in cell: MessageCell) {
        print("didTapMessage")
    }

    func didTapAvatar(in cell: MessageCell) {
        print("didTapAvatar")
    }
}

extension MessageViewController : SendMessageBarDelegate {
    func sendMessageBar(sendText: String) -> Bool? {
        return interactor?.sendMessage(content: Drafty(content: sendText))
    }

    func sendMessageBar(attachment: Bool) {
        // TODO: Show file picker
    }

    func sendMessageBar(textChangedTo text: String) {
        interactor?.sendTypingNotification()
    }
}
