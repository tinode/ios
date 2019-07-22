//
//  MessageViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

protocol MessageDisplayLogic: class {
    func updateTitleBar(icon: UIImage?, title: String?, online: Bool)
    func setOnline(online: Bool)
    func runTypingAnimation()
    func displayChatMessages(messages: [StoredMessage])
    func reloadMessage(withSeqId seqId: Int)
    func updateProcess(forMsgId msgId: Int64, progress: Float)
    func applyTopicPermissions()
    func endRefresh()
    func dismiss()
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
        // Horizontal space between delivery marker and the edge of the message bubble
        static let kDeliveryMarkerPadding: CGFloat = 10
        // Horizontal space between delivery marker and timestamp
        static let kTimestampPadding: CGFloat = 0
        // Approximate width of the timestamp
        static let kTimestampWidth: CGFloat = 48
        // Progress bar paddings.
        static let kProgressBarLeftPadding: CGFloat = 10
        static let kProgressBarRightPadding: CGFloat = 25

        // Color of "read" delivery marker.
        static let kDeliveryMarkerTint = UIColor(red: 19/255, green: 144/255, blue:255/255, alpha: 0.8)
        // Color of all other markers.
        static let kDeliveryMarkerColor = UIColor.gray.withAlphaComponent(0.7)

        // Light gray color: outgoing messages
        static let kOutgoingBubbleColor = UIColor(red: 230/255, green: 230/255, blue: 230/255, alpha: 1)
        // And corresponding text color
        static let kOutgoingTextColor = UIColor.darkText
        // Bright green color
        static let kIncomingBubbleColor = UIColor(red: 69/255, green: 193/255, blue: 89/255, alpha: 1)
        // And corresponding font color
        static let kIncomingTextColor = UIColor.white

        static let kContentFont = UIFont.preferredFont(forTextStyle: .body)

        static let kSenderNameFont = UIFont.preferredFont(forTextStyle: .caption2)
        static let kTimestampFont = UIFont.preferredFont(forTextStyle: .caption2)
        static let kSenderNameLabelHeight: CGFloat = 16
        static let kNewDateFont = UIFont.boldSystemFont(ofSize: 10)
        static let kNewDateLabelHeight: CGFloat = 24
        // Vertical spacing between messages from the same user
        static let kVerticalCellSpacing: CGFloat = 2
        // Additional vertical spacing between messages from different users in P2P topics.
        static let kAdditionalP2PVerticalCellSpacing: CGFloat = 4
        static let kMinimumCellWidth: CGFloat = 90
        // This is the space between the other side of the message and the edge of screen.
        // I.e. for incoming messages the space between the message and the *right* edge, for
        // outfoing between the message and the left edge.
        static let kFarSideHorizontalSpacing: CGFloat = 45

        // Insets around collection view, i.e. main view padding
        static let kCollectionViewInset = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 2)

        // Insets for the message bubble relative to collectionView: bubble should not touch the sides of the screen.
        static let kIncomingContainerPadding = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: Constants.kFarSideHorizontalSpacing)
        static let kOutgoingContainerPadding = UIEdgeInsets(top: 0, left: Constants.kFarSideHorizontalSpacing, bottom: 0, right: 0)

        // Insets around content inside the message bubble.
        static let kIncomingMessageContentInset = UIEdgeInsets(top: 4, left: 18, bottom: 13, right: 14)
        static let kOutgoingMessageContentInset = UIEdgeInsets(top: 4, left: 14, bottom: 13, right: 18)

        // Carve out for timestamp and delivery marker in the bottom-right corner.
        static let kIncomingMetadataCarveout = "     "
        static let kOutgoingMetadataCarveout = "       "
    }

    /// The `sendMessageBar` is used as the `inputAccessoryView` in the view controller.
    private lazy var sendMessageBar: SendMessageBar = {
        let view = SendMessageBar()
        view.autoresizingMask = .flexibleHeight
        return view
    }()

    /// Avatar in the NavBar
    private lazy var navBarAvatarView: AvatarWithOnlineIndicator = {
        let avatarIcon = AvatarWithOnlineIndicator()
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(navBarAvatarTapped(tapGestureRecognizer:)))
        avatarIcon.isUserInteractionEnabled = true
        avatarIcon.addGestureRecognizer(tapGestureRecognizer)
        return avatarIcon
    }()

    /// Pointer to the view holding messages.
    weak var collectionView: MessageView!

    var interactor: (MessageBusinessLogic & MessageDataStore)?
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
    // TODO: this is ugly. Move this to MVC+SendMessageBarDelegate.swift
    var imagePicker: ImagePicker?

    private var noteTimer: Timer? = nil

    // Messages to be displayed
    var messages: [Message] = []
    // For updating individual messages, we need:
    // * Tinode sequence id -> messages offset.
    var messageSeqIdIndex: [Int:Int] = [:]
    // * Database message id -> message offset.
    var messageDbIdIndex: [Int64:Int] = [:]

    // Cache of message cell sizes. Calculation of cell sizes is heavy. Caching the result to improve scrolling performance.
    // var cellSizeCache: [CGSize?] = []

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

    private func addAppStateObservers() {
        // App state observers.
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.appGoingInactive),
            name: UIApplication.willResignActiveNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.appBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
    }
    private func removeAppStateObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willResignActiveNotification,
            object: nil)
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
    }

    private func setup() {
        myUID = Cache.getTinode().myUid
        self.imagePicker = ImagePicker(presentationController: self, delegate: self)

        let interactor = MessageInteractor()
        let presenter = MessagePresenter()
        interactor.presenter = presenter
        presenter.viewController = self

        self.interactor = interactor
        addAppStateObservers()
    }

    @objc
    func appBecameActive() {
        self.interactor?.attachToTopic()
    }
    @objc
    func appGoingInactive() {
        self.interactor?.cleanup()
        self.interactor?.leaveTopic()
    }

    // MARK: lifecycle

    deinit {
        removeKeyboardObservers()
        // removeMenuControllerObservers()
        removeAppStateObservers()
        // Clean up.
        appGoingInactive()
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
        collectionView.layoutMargins = Constants.kCollectionViewInset
        view.addSubview(collectionView)
        self.collectionView = collectionView

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

    public func applyTopicPermissions() {
        DispatchQueue.main.async {
            // Make sure the view is visible.
            guard self.isViewLoaded && ((self.view?.window) != nil) else { return }
            if !(self.topic?.isReader ?? false) {
                self.collectionView.showNoAccessOverlay()
            } else {
                self.collectionView.removeNoAccessOverlay()
            }
            if self.topic?.isWriter ?? false {
                self.sendMessageBar.removeNotAvailableOverlay()
                if let acs = self.topic?.peer?.acs,
                    acs.isJoiner(for: .want) && (acs.missing?.description.contains("RW") ?? false) {
                    self.sendMessageBar.showPeersMessagingDisabledOverlay()
                }
            } else {
                self.sendMessageBar.showNotAvailableOverlay()
            }
            // We are offered to join a chat.
            if let acs = self.topic?.accessMode, acs.isJoiner(for: Acs.Side.given) && (acs.excessive?.description.contains("RW") ?? false) {
                self.showInvitationDialog()
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let layout = collectionView?.collectionViewLayout as? MessageViewLayout {
            layout.delegate = self
        }

        self.collectionView.dataSource = self
        sendMessageBar.delegate = self

        view.backgroundColor = .white
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Otherwise setting contentInset after viewDidAppear will be animated.
        if isInitialLayout {
            defer { isInitialLayout = false }
            addKeyboardObservers()
        }
    }
    @objc private func processNotifications() {
        self.interactor?.sendReadNotification()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !(self.interactor?.setup(topicName: self.topicName) ?? false) {
            print("error in interactor setup for \(String(describing: self.topicName))")
        }
        self.interactor?.attachToTopic()
        self.interactor?.loadMessages()
        self.interactor?.sendReadNotification()
        if #available(iOS 10.0, *) {
            self.noteTimer = Timer.scheduledTimer(
                withTimeInterval: 1,
                repeats: true,
                block: { _ in
                    //self.interactor?.sendReadNotification()
                    self.processNotifications()
                })
        } else {
            // Fallback on earlier versions
            self.noteTimer = Timer.scheduledTimer(
                timeInterval: 1,
                target: self,
                selector: #selector(self.processNotifications), userInfo: nil, repeats: true)
        }
        self.applyTopicPermissions()
    }
    override func viewWillDisappear(_ animated: Bool) {
        if let viewControllers = self.navigationController?.viewControllers, viewControllers.count > 1, viewControllers[viewControllers.count - 2] === self {
            // It's a push. No need to detach.
            print("keeping topic attached")
        } else {
            self.interactor?.cleanup()
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.noteTimer?.invalidate()
    }

    @objc func loadNextPage() {
        self.interactor?.loadNextPage()
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "Messages2TopicInfo" {
            let destinationVC = segue.destination as! TopicInfoViewController
            destinationVC.topicName = self.topicName ?? ""
        }
    }

    @objc func navBarAvatarTapped(tapGestureRecognizer: UITapGestureRecognizer) {
        performSegue(withIdentifier: "Messages2TopicInfo", sender: nil)
    }
}

// Methods for updating title area and refreshing messages.
extension MessageViewController: MessageDisplayLogic {
    private func showInvitationDialog() {
        guard self.presentedViewController == nil else { return }
        let attrs = [ NSAttributedString.Key.font: UIFont.systemFont(ofSize: 20.0) ]
        let title = NSAttributedString(string: "New Chat", attributes: attrs)
        let alert = UIAlertController(
            title: nil,
            message: "You are invited to start a new chat. What would you like?",
            preferredStyle: .actionSheet)
        alert.setValue(title, forKey: "attributedTitle")
        alert.addAction(UIAlertAction(
            title: "Accept", style: .default,
            handler: { action in
                print("ok clicked")
                self.interactor?.acceptInvitation()
        }))
        alert.addAction(UIAlertAction(
            title: "Ignore", style: .default,
            handler: { action in
                print("ignore clicked")
                self.interactor?.ignoreInvitation()
        }))
        alert.addAction(UIAlertAction(
            title: "Block", style: .default,
            handler: { action in
                print("block clicked")
                self.interactor?.blockTopic()
        }))
        self.present(alert, animated: true)
    }

    func updateTitleBar(icon: UIImage?, title: String?, online: Bool) {
        self.navigationItem.title = title ?? "Undefined"

        navBarAvatarView.set(icon: icon, title: title, id: topicName, online: online)
        navBarAvatarView.translatesAutoresizingMaskIntoConstraints = false
        navBarAvatarView.bounds = CGRect(x: 0, y: 0, width: Constants.kNavBarAvatarSmallState, height: Constants.kNavBarAvatarSmallState)

        NSLayoutConstraint.activate([
                navBarAvatarView.heightAnchor.constraint(equalToConstant: Constants.kNavBarAvatarSmallState),
                navBarAvatarView.widthAnchor.constraint(equalTo: navBarAvatarView.heightAnchor)
            ])

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: navBarAvatarView)
    }
    func setOnline(online: Bool) {
        navBarAvatarView.setOnline(online: online)
    }
    func runTypingAnimation() {
        navBarAvatarView.presentTypingAnimation(steps: 30)
    }
    func displayChatMessages(messages: [StoredMessage]) {
        let oldData = self.messages
        let newData: [StoredMessage] = messages.reversed()
        self.messageSeqIdIndex = newData.enumerated().reduce([Int:Int]()) { (dict, item) -> [Int:Int] in
            var dict = dict
            dict[item.element.seqId] = item.offset
            return dict
        }
        self.messageDbIdIndex = newData.enumerated().reduce([Int64:Int]()) { (dict, item) -> [Int64:Int] in
            var dict = dict
            dict[item.element.msgId] = item.offset
            return dict
        }

        if oldData.isEmpty || newData.isEmpty {
            self.messages = newData
            collectionView.reloadData()
        } else {
            // Get indexes of inserted and deleted items.
            let diff = Utils.diffMessageArray(sortedOld: oldData, sortedNew: newData)

            // Each insertion or deletion may change the appearance of the preceeding and following messages.
            // Calculate indexes of all items which need to be updated.
            var refresh: [Int] = []
            for index in diff.mutated {
                if index > 0 {
                    // Refresh the preceeding item.
                    refresh.append(index - 1)
                }
                if index < newData.count - 1 {
                    // Refresh the following item.
                    refresh.append(index + 1)
                }
                if index < newData.count {
                    refresh.append(index)
                }
            }
            // Ensure uniqueness of values. No need to reload newly inserted values.
            refresh = Array(Set(refresh).subtracting(Set(diff.inserted)))

            print("Message diff: \(diff); refresh: \(refresh)")

            collectionView.performBatchUpdates({ () -> Void in
                self.messages = newData
                if diff.removed.count > 0 {
                    collectionView.deleteItems(at: diff.removed.map { IndexPath(item: $0, section: 0) })
                }
                if diff.inserted.count > 0 {
                    collectionView.insertItems(at: diff.inserted.map { IndexPath(item: $0, section: 0) })
                }
                //if refresh.count > 0 {
                    // collectionView.reloadItems(at: refresh.map { IndexPath(item: $0, section: 0) })
                //}
                }, completion: nil)
        }
        collectionView.layoutIfNeeded()
        collectionView.scrollToBottom()
    }
    func reloadMessage(withSeqId seqId: Int) {
        if let index = self.messageSeqIdIndex[seqId] {
            self.collectionView.reloadItems(at: [IndexPath(row: index, section: 0)])
        }
    }
    func updateProcess(forMsgId msgId: Int64, progress: Float) {
        if let index = self.messageDbIdIndex[msgId],
            let cell = self.collectionView.cellForItem(at: IndexPath(row: index, section: 0)) as? MessageCell {
            cell.progressBar.progress = progress
        }
    }
    func endRefresh() {
        DispatchQueue.main.async {
            self.refreshControl.endRefreshing()
        }
    }
    func dismiss() {
        DispatchQueue.main.async {
            self.navigationController?.popViewController(animated: true)
            self.dismiss()
        }
    }
}

// Methods for filling message with content and layout out message subviews.
extension MessageViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        self.collectionView.toggleNoMessagesNote(on: messages.isEmpty)
        return messages.count
    }

    // Configure message cell for the given index: fill data and lay out subviews.
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: MessageCell.self), for: indexPath) as! MessageCell

        // To capture taps.
        cell.delegate = self

        // Cell content
        let message = messages[indexPath.item]

        // Get cell attributes from cache.
        let attributes = collectionView.layoutAttributesForItem(at: indexPath) as! MessageViewLayoutAttributes

        // Set colors and fill out content except for the avatar. The maxumum size is needed for placing attached images.
        configureCell(cell: cell, with: message, at: indexPath)

        cell.avatarView.frame = attributes.avatarFrame
        if attributes.avatarFrame != .zero  {
            // The avatar image should be assigned after setting the size. Otherwise it may be drawn twice.
            if let sub = topic?.getSubscription(for: message.from) {
                cell.avatarView.set(icon: sub.pub?.photo?.image(), title: sub.pub?.fn, id: message.from)
            } else {
                cell.avatarView.set(icon: nil, title: nil, id: message.from)
                print("Subscription not found for \(message.from ?? "nil")")
            }
        }

        // Sender name under the avatar.
        cell.senderNameLabel.frame = attributes.senderNameFrame

        cell.containerView.frame = attributes.containerFrame

        // Content: RichTextLabel.
        cell.content.frame = attributes.contentFrame

        cell.deliveryMarker.frame = attributes.deliveryMarkerFrame

        cell.timestampLabel.sizeToFit()
        cell.timestampLabel.frame = attributes.timestampFrame

        cell.newDateLabel.frame = attributes.newDateFrame

        // Draw the bubble
        bubbleDecorator(for: message, at: indexPath)(cell.containerView)

        cell.progressBar.frame = attributes.progressBarFrame
        cell.cancelUploadButton.frame = attributes.cancelUploadButtonFrame

        return cell
    }

    private func configureCell(cell: MessageCell, with message: Message, at indexPath: IndexPath) {

        cell.seqId = message.seqId

        cell.content.backgroundColor = nil
        if isFromCurrentSender(message: message) {
            cell.containerView.backgroundColor = Constants.kOutgoingBubbleColor
            cell.content.textColor = .darkText
        } else {
            cell.containerView.backgroundColor = Constants.kIncomingBubbleColor
            cell.content.textColor = .white
        }

        cell.content.font = Constants.kContentFont

        let storedMessage = message as! StoredMessage
        if let attributedText = storedMessage.cachedContent {
            let carveout = (isFromCurrentSender(message: message) ? Constants.kOutgoingMetadataCarveout : Constants.kIncomingMetadataCarveout)
            let text = NSMutableAttributedString(attributedString: attributedText)
            text.append(NSAttributedString(string: carveout, attributes: [.font: Constants.kContentFont]))
            cell.content.attributedText = text
        }

        if let (image, tint) = deliveryMarker(for: message, at: indexPath) {
            cell.deliveryMarker.image = image
            cell.deliveryMarker.tintColor = tint
        }
        if let ts = message.ts {
            cell.timestampLabel.text = RelativeDateFormatter.shared.timeOnly(from: ts)
            cell.timestampLabel.textColor = isFromCurrentSender(message: message) ? UIColor.gray : UIColor.lightText
        }
        cell.newDateLabel.attributedText = newDateLabel(for: message, at: indexPath)
        cell.senderNameLabel.attributedText = senderFullName(for: message, at: indexPath)

        if shouldShowProgressBar(for: message) {
            cell.showProgressBar()
        }
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

    func deliveryMarker(for message: Message, at indexPath: IndexPath) -> (UIImage, UIColor)? {
        guard isFromCurrentSender(message: message), let topic = topic else { return nil }

        let iconName: String
        var tint: UIColor = Constants.kDeliveryMarkerColor
        if message.isPending {
            iconName = "schedule_48"
        } else {
            if topic.msgReadCount(seq: message.seqId) > 0 {
                iconName = "done_all_48"
                tint = Constants.kDeliveryMarkerTint
            } else if topic.msgRecvCount(seq: message.seqId) > 0 {
                iconName = "done_all_48"
            } else {
                iconName = "done_48"
            }
        }

        return (UIImage(named: iconName)!, tint)
    }

    // Returns closure which adds message bubble mask to the supplied UIView.
    func bubbleDecorator(for message: Message, at indexPath: IndexPath) -> (UIView) -> Void {
        let isIncoming = !isFromCurrentSender(message: message)

        let breakBefore = !isPreviousMessageSameSender(at: indexPath) || !isPreviousMessageSameDate(at: indexPath)
        let breakAfter = !isNextMessageSameSender(at: indexPath) || !isNextMessageSameDate(at: indexPath)

        let style: MessageBubbleDecorator.Style
        switch true {
        case breakBefore && breakAfter:
            style = .single
        case breakBefore:
            style = .first
        case breakAfter:
            style = .last
        default:
            style = .middle
        }

        return { view in
            let path = MessageBubbleDecorator.draw(view.bounds, isIncoming: isIncoming, style: style)
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

    // Should we show upload progress bar for reference attachment messages?
    func shouldShowProgressBar(for message: Message) -> Bool {
        return message.isDraft && (message.content?.isReferenceAttachment ?? false)
    }

    func isNewDateLabelVisible(at indexPath: IndexPath) -> Bool {
        return !isPreviousMessageSameDate(at: indexPath)
    }
}

// Message size calculation
extension MessageViewController : MessageViewLayoutDelegate {

    // MARK: MessageViewLayoutDelegate method

    // Claculate positions and sizes of all subviews in a cell.
    func collectionView(_ collectionView: UICollectionView, fillAttributes attr: MessageViewLayoutAttributes) {
        let indexPath = attr.indexPath

        // Cell content
        let message = messages[indexPath.item]

        // Is this an outgoing message?
        let isOutgoing = isFromCurrentSender(message: message)
        // The message set has avatars.
        let hasAvatars = avatarsVisible(message: message)
        // This message has an avatar.
        let isAvatarVisible = shouldShowAvatar(for: message, at: indexPath)

        // Insets for the message bubble relative to collectionView: bubble should not touch the sides of the screen.
        let containerPadding = isOutgoing ? Constants.kOutgoingContainerPadding : Constants.kIncomingContainerPadding

        // Get cell size.
        let cellSize = calcCellSize(forItemAt: indexPath)
        attr.cellSpacing = Constants.kVerticalCellSpacing

        // Height of the field with the current date above the first message of the day.
        let newDateLabelHeight = calcNewDateLabelHeight(at: indexPath)

        // This is the height of the field with the sender's name.
        let senderNameLabelHeight = isAvatarVisible ? Constants.kSenderNameLabelHeight : 0

        if isAvatarVisible {
            attr.avatarFrame = CGRect(x: 0, y: cellSize.height - Constants.kAvatarSize - senderNameLabelHeight, width: Constants.kAvatarSize, height: Constants.kAvatarSize)

            // Sender name under the avatar.
            attr.senderNameFrame = CGRect(origin: CGPoint(x: 0, y: cellSize.height - senderNameLabelHeight), size: CGSize(width: cellSize.width, height: senderNameLabelHeight))
        } else {
            attr.avatarFrame = .zero
            attr.senderNameFrame = .zero
        }

        // Additional left padding in group topics with avatar
        let avatarPadding = hasAvatars ? Constants.kAvatarSize : 0

        // Size of the message bubble.
        let containerSize = calcContainerSize(for: message, avatarsVisible: hasAvatars)
        // isFromCurrent Sender ? Flush container right : flush left.
        let originX = isOutgoing ? cellSize.width - avatarPadding - containerSize.width - containerPadding.right : avatarPadding + containerPadding.left
        attr.containerFrame = CGRect(origin: CGPoint(x: originX, y: newDateLabelHeight + containerPadding.top), size: containerSize)

        // Content: RichTextLabel.
        let contentInset = isOutgoing ? Constants.kOutgoingMessageContentInset : Constants.kIncomingMessageContentInset
        attr.contentFrame = CGRect(x: contentInset.left, y: contentInset.top, width: attr.containerFrame.width - contentInset.left - contentInset.right, height: attr.containerFrame.height - contentInset.top - contentInset.bottom)

        var rightEdge = CGPoint(x: attr.containerFrame.width - Constants.kDeliveryMarkerPadding, y: attr.containerFrame.height - Constants.kDeliveryMarkerSize)
        if isOutgoing {
            rightEdge.x -= Constants.kDeliveryMarkerSize
            attr.deliveryMarkerFrame = CGRect(x: rightEdge.x, y: rightEdge.y, width: Constants.kDeliveryMarkerSize, height: Constants.kDeliveryMarkerSize)
        } else {
            attr.deliveryMarkerFrame = .zero
        }

        attr.timestampFrame = CGRect(x: rightEdge.x - Constants.kTimestampWidth - Constants.kTimestampPadding, y: rightEdge.y, width: Constants.kTimestampWidth, height: Constants.kDeliveryMarkerSize)

        // New date label
        if newDateLabelHeight > 0 {
            attr.newDateFrame = CGRect(origin: CGPoint(x: 0, y: attr.containerFrame.minY - containerPadding.top - newDateLabelHeight), size: CGSize(width: cellSize.width, height: newDateLabelHeight))
        } else {
            attr.newDateFrame = .zero
        }

        if shouldShowProgressBar(for: message) {
            let leftEdge = CGPoint(x: attr.contentFrame.origin.x,
                                   y: attr.contentFrame.height + Constants.kDeliveryMarkerSize / 2)
            attr.progressBarFrame =
                CGRect(x: leftEdge.x, y: leftEdge.y,
                       width: attr.containerFrame.width - attr.timestampFrame.width - attr.deliveryMarkerFrame.width - Constants.kProgressBarRightPadding - 20,
                       height: attr.timestampFrame.height)
            attr.cancelUploadButtonFrame =
                CGRect(x: leftEdge.x + attr.progressBarFrame.width + 4, y: leftEdge.y - 2, width: 8, height: 8)
        } else {
            attr.progressBarFrame = .zero
            attr.cancelUploadButtonFrame = .zero
        }

        attr.frame = CGRect(origin: CGPoint(), size: cellSize)
    }

    // MARK: supporting methods

    // Calculate and cache message cell size
    func calcCellSize(forItemAt indexPath: IndexPath) -> CGSize {
        //if let size = cellSizeCache[indexPath.item] {
        //    return size
        // }

        let message = messages[indexPath.item]
        let hasAvatars = avatarsVisible(message: message)
        let containerHeight = calcContainerSize(for: message, avatarsVisible: hasAvatars).height
        let size = CGSize(width: calcCellWidth(), height: calcCellHeightFromContent(for: message, at: indexPath, containerHeight: containerHeight, avatarsVisible: hasAvatars))
        // cellSizeCache[indexPath.item] = size
        return size
    }

    func calcCellWidth() -> CGFloat {
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
        let attributedText = NSMutableAttributedString()

        let carveout = isFromCurrentSender(message: message) ? Constants.kOutgoingMetadataCarveout : Constants.kIncomingMetadataCarveout

        let textColor = isFromCurrentSender(message: message) ? Constants.kOutgoingTextColor : Constants.kIncomingTextColor

        let storedMessage = message as! StoredMessage
        if let content = storedMessage.attributedContent(fitIn: CGSize(width: maxWidth, height: collectionView.frame.height * 0.66), withDefaultAttributes: [.font: Constants.kContentFont, .foregroundColor: textColor]) {
            attributedText.append(content)
        } else {
            attributedText.append(NSAttributedString(string: "none", attributes: [.font: Constants.kContentFont]))
        }
        attributedText.append(NSAttributedString(string: carveout, attributes: [.font: Constants.kContentFont]))
        let size = attributedText.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).integral.size
        return size
    }
}

// Methods for handling taps in messages.

extension MessageViewController : MessageCellDelegate {
    func didLongTap(in cell: MessageCell) {
        createPopupMenu(in: cell)
    }

    func didTapContent(in cell: MessageCell, url: URL?) {
        guard let url = url else { return }

        print("didTapContent URL=\(url.absoluteString)")

        if url.scheme == "tinode" {
            switch url.path {
            case "/post":
                handleButtonPost(in: cell, data: url)
            case "/small-attachment":
                handleSmallAttachment(in: cell, using: url)
                print("small attachment - \(url)")
            case "/large-attachment":
                handleLargeAttachment(in: cell, using: url)
                print("large attachment - \(url)")
            default:
                print("Unknown tinode:// action '\(url.path)'")
                break
            }
            // TODO: post message, save attachment.
            return
        }

        if #available(iOS 10.0, *) {
            UIApplication.shared.open(url)
        } else {
            UIApplication.shared.openURL(url)
        }
    }

    func didTapMessage(in cell: MessageCell) {
        print("didTapMessage")
    }

    func didTapAvatar(in cell: MessageCell) {
        print("didTapAvatar")
    }

    func createPopupMenu(in cell: MessageCell) {
        // Set up the shared UIMenuController
        let copyMenuItem = MessageMenuItem(title: "Copy", action: #selector(copyMessageContent(sender:)), seqId: cell.seqId)
        let deleteMenuItem = MessageMenuItem(title: "Delete", action: #selector(deleteMessage(sender:)), seqId: cell.seqId)
        UIMenuController.shared.menuItems = [copyMenuItem, deleteMenuItem]

        // Tell the menu controller the first responder's frame and its super view
        UIMenuController.shared.setTargetRect(cell.frame, in: self.collectionView)

        // Animate the menu onto view
        UIMenuController.shared.setMenuVisible(true, animated: true)
    }

    @objc func copyMessageContent(sender: UIMenuController) {
        guard let menuItem = sender.menuItems?.first as? MessageMenuItem, menuItem.seqId > 0, let msgIndex = messageSeqIdIndex[menuItem.seqId] else { return }

        let msg = messages[msgIndex]

        var senderName: String?
        if let sub = topic?.getSubscription(for: msg.from), let pub = sub.pub {
            senderName = pub.fn
        }
        senderName = senderName ?? "Unknown \(msg.from ?? "none")"
        UIPasteboard.general.string = "[\(senderName!)]: \(msg.content?.string ?? ""); \(RelativeDateFormatter.shared.shortDate(from: msg.ts))"
    }

    @objc func deleteMessage(sender: UIMenuController) {
        guard let menuItem = sender.menuItems?.first as? MessageMenuItem, menuItem.seqId > 0 else { return }
        interactor?.deleteMessage(seqId: menuItem.seqId)
    }

    func didTapOutsideContent(in cell: MessageCell) {
        self.sendMessageBar.inputField.resignFirstResponder()
    }

    func didTapCancelUpload(in cell: MessageCell) {
        guard let topicId = self.topicName,
            let msgIdx = self.messageSeqIdIndex[cell.seqId] else { return }
        if Cache.getLargeFileHelper().cancelUpload(
            topicId: topicId, msgId: self.messages[msgIdx].msgId) {
            print("cancelled upload")
        }
    }

    private func handleButtonPost(in cell: MessageCell, data url: URL) {
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String : String]?
        if let queryItems = parts?.queryItems {
            query = [:]
            for item in queryItems {
                query![item.name] = item.value
            }
        }
        let newMsg = Drafty(content: query?["title"] ?? "undefined")
        var json: [String : JSONValue] = [:]
        // {"seq":6,"resp":{"yes":1}}
        if let name = query?["name"], let val = query?["val"] {
            var resp: [String : JSONValue] = [:]
            resp[name] = JSONValue.string(val)
            json["resp"] = JSONValue.dict(resp)
        }
        json["seq"] = JSONValue.int(cell.seqId)

        _ = interactor?.sendMessage(content: newMsg.attachJSON(json))
    }
    static func extractAttachment(from cell: MessageCell) -> [Data]? {
        guard let text = cell.content.attributedText else { return nil }
        var parts = [Data]()

        let range = NSMakeRange(0, text.length)
        text.enumerateAttributes(in: range, options: NSAttributedString.EnumerationOptions(rawValue: 0)) { (object, range, stop) in
            if object.keys.contains(.attachment) {
                if let attachment = object[.attachment] as? NSTextAttachment, let data = attachment.contents {
                    parts.append(data)
                }
            }
        }
        return parts
    }
    private func handleLargeAttachment(in cell: MessageCell, using url: URL) {
        guard let data = MessageViewController.extractAttachment(from: cell), !data.isEmpty else { return }
        let downloadFrom = String(decoding: data[0], as: UTF8.self)
        guard let url = URL(string: downloadFrom) else { return }
        Cache.getLargeFileHelper().startDownload(from: url)
    }
    private func handleSmallAttachment(in cell: MessageCell, using url: URL) {
        // TODO: move logic to MessageInteractor.
        guard let data = MessageViewController.extractAttachment(from: cell), !data.isEmpty else { return }
        let d = data[0]
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var filename: String?
        if let queryItems = components?.queryItems {
            for queryItem in queryItems {
                if queryItem.name == "filename" {
                    filename = queryItem.value
                    break
                }
            }
        }
        guard filename != nil else { return }
        let documentsUrl: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsUrl.appendingPathComponent(filename!)
        do {
            try d.write(to: destinationURL)
            // TODO: show preview.
        } catch {
            print("failed to save \(filename!)")
        }
    }
}
