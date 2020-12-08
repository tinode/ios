//
//  MessageViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

protocol MessageDisplayLogic: class {
    func switchTopic(topic: String?)
    func updateTitleBar(icon: UIImage?, title: String?, online: Bool?)
    func setOnline(online: Bool?)
    func runTypingAnimation()
    func displayChatMessages(messages: [StoredMessage])
    func reloadAllMessages()
    func reloadMessages(fromSeqId loId: Int, toSeqId hiId: Int)
    func updateProgress(forMsgId msgId: Int64, progress: Float)
    func applyTopicPermissions(withError: Error?)
    func endRefresh()
    func dismissVC()
}

class MessageViewController: UIViewController {
    // Other controllers may send these notification to MessageViewController which will execute corresponding send message action.
    public static let kNotificationSendAttachment = "SendAttachment"

    // MARK: static parameters
    private enum Constants {
        /// Size of the avatar in the nav bar in small state.
        static let kNavBarAvatarSmallState: CGFloat = 32

        /// Size of the avatar in group topics.
        static let kAvatarSize: CGFloat = 30

        static let kProgressViewHeight: CGFloat = 30

        // Size of delivery marker (checkmarks etc)
        static let kDeliveryMarkerSize: CGFloat = 16
        // Horizontal space between delivery marker and the edge of the message bubble
        static let kDeliveryMarkerPadding: CGFloat = 10
        // Horizontal space between delivery marker and timestamp
        static let kTimestampPadding: CGFloat = 0
        // Approximate width of the timestamp
        static let kTimestampWidth: CGFloat = 50
        // Progress bar paddings.
        static let kProgressBarLeftPadding: CGFloat = 10
        static let kProgressBarRightPadding: CGFloat = 25

        // Color of "read" delivery marker.
        static let kDeliveryMarkerTint = UIColor(red: 19/255, green: 144/255, blue:255/255, alpha: 0.8)
        // Color of all other markers.
        static let kDeliveryMarkerColor = UIColor.gray.withAlphaComponent(0.7)

        // Light/dark gray color: outgoing messages
        static let kOutgoingBubbleColorLight = UIColor(red: 230/255, green: 230/255, blue: 230/255, alpha: 1)
        static let kOutgoingBubbleColorDark = UIColor(red: 51/255, green: 51/255, blue: 51/255, alpha: 1)
        // And corresponding text color
        static let kOutgoingTextColorLight = UIColor.darkText
        static let kOutgoingTextColorDark = UIColor.lightText
        // Bright/dark green color
        static let kIncomingBubbleColorLight = UIColor(red: 69/255, green: 193/255, blue: 89/255, alpha: 1)
        static let kIncomingBubbleColorDark = UIColor(red: 40/255, green: 120/255, blue: 60/255, alpha: 1)
        // And corresponding font color
        static let kIncomingTextColorLight = UIColor.white
        static let kIncomingTextColorDark = UIColor.lightText
        // Meta-messages, such as "Content deleted".
        static let kDeletedMessageBubbleColorLight = UIColor(fromHexCode: 0xffe3f2fd)
        static let kDeletedMessageBubbleColorDark = UIColor(fromHexCode: 0xff263238)
        static let kDeletedMessageTextColor = UIColor.gray

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
        static let kMinimumCellWidth: CGFloat = 94
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
        static let kDeletedMessageContentInset = UIEdgeInsets(top: 4, left: 14, bottom: 0, right: 14)

        // Carve out for timestamp and delivery marker in the bottom-right corner.
        static let kIncomingMetadataCarveout = "     "
        static let kOutgoingMetadataCarveout = "       "

        // Thresholds for tracking update batch stats/UI refresh.
        // When too many messages (batch) come in a quick succession,
        // we refresh the UI in full in order to avoid UI glitches.
        static let kUpdateBatchFullRefreshThreshold = 5
        // Max time difference between successive messages to count them as one batch.
        static let kUpdateBatchTimeDeltaThresholdMs : Int64 = 300
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
            let tinode = Cache.tinode
            topic = tinode.getTopic(topicName: topicName!) as? DefaultComTopic
            if topic == nil {
                topic = tinode.newTopic(for: topicName!) as? DefaultComTopic
            }
        }
    }
    var topicType: TopicType?
    var myUID: String?
    var topic: DefaultComTopic?
    // TODO: this is ugly. Move this to MVC+SendMessageBarDelegate.swift
    var imagePicker: ImagePicker?

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

    // Size of the present update batch.
    private var updateBatchSize = 0
    // Last message received timestamp - for tracking batches.
    private var lastMessageReceived = Date.distantPast

    // The two below indicate whether to send typing notifications and read receipts.
    // Determined by the user specified account notifications settings.
    internal var sendTypingNotifications = false
    internal var sendReadReceipts = false

    private var textSizeHelper = TextSizeHelper()

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
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.deviceRotated),
            name: UIDevice.orientationDidChangeNotification, object: nil)
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
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification,
            object: nil)
    }

    private func setup() {
        myUID = Cache.tinode.myUid
        self.imagePicker = ImagePicker(presentationController: self, delegate: self, editable: false)

        let interactor = MessageInteractor()
        let presenter = MessagePresenter()
        interactor.presenter = presenter
        presenter.viewController = self

        // Notifications settings.
        self.sendTypingNotifications = SharedUtils.kAppDefaults.bool(forKey: SharedUtils.kTinodePrefTypingNotifications)
        self.sendReadReceipts = SharedUtils.kAppDefaults.bool(forKey: SharedUtils.kTinodePrefReadReceipts)

        self.interactor = interactor
        addAppStateObservers()
    }

    @objc
    func appBecameActive() {
        self.interactor?.setup(topicName: topicName, sendReadReceipts: self.sendReadReceipts)
        self.interactor?.attachToTopic(interactively: true)
    }
    @objc
    func appGoingInactive() {
        self.interactor?.cleanup()
        self.interactor?.leaveTopic()
    }
    @objc
    func deviceRotated() {
        // Invalidate cached content in the messages since it was
        // tailored for the old device orientation.
        self.messages.forEach { ($0 as? StoredMessage)?.cachedContent = nil }
        // Force a full redraw so the view can readjust the messages
        // in the view for the new screen dimensions.
        self.collectionView?.reloadDataAndKeepOffset()
    }

    // MARK: lifecycle

    deinit {
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

        // Receive notifications from FilePreviewController with an attachment to upload or send.
        NotificationCenter.default.addObserver(self, selector: #selector(sendAttachment(notification:)), name: Notification.Name(MessageViewController.kNotificationSendAttachment), object: nil)

        // Collection View setup
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.keyboardDismissMode = .interactive
        collectionView.alwaysBounceVertical = true
        collectionView.layoutMargins = Constants.kCollectionViewInset
        view.addSubview(collectionView)
        self.collectionView = collectionView

        collectionView.addSubview(refreshControl)
        refreshControl.addTarget(self, action: #selector(loadNextPage), for: .valueChanged)

        // Setup UICollectionView constraints: fill the screen
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        let top = collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor) // FIXME: maybe it needs some spacing
        let bottom = collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        let leading = collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        let trailing = collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        NSLayoutConstraint.activate([top, bottom, trailing, leading])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let layout = collectionView?.collectionViewLayout as? MessageViewLayout {
            layout.delegate = self
        }

        self.collectionView.dataSource = self
        sendMessageBar.delegate = self

        self.setInterfaceColors()

        if (self.interactor?.setup(topicName: self.topicName, sendReadReceipts: self.sendReadReceipts) ?? false) {
            self.interactor?.deleteFailedMessages()
            self.interactor?.loadMessages()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Otherwise setting contentInset after viewDidAppear will be animated.
        if isInitialLayout {
            defer { isInitialLayout = false }
            addKeyboardObservers()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        self.setInterfaceColors()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: sendMessageBar.frame.height, right: 0)

        self.interactor?.attachToTopic(interactively: true)
        self.interactor?.loadMessages()
        self.interactor?.sendReadNotification(explicitSeq: nil, when: .now() + .seconds(1))
        self.applyTopicPermissions()
    }
    // Continue listening for events even when the VC isn't visible.
    // TODO: remote this.
    // override func viewWillDisappear(_ animated: Bool) {
    //    if let viewControllers = self.navigationController?.viewControllers, viewControllers.count > 1, viewControllers[viewControllers.count - 2] === self {
    //        // It's a push. No need to detach.
    //        print("keeping topic attached")
    //    } else {
    //        self.interactor?.cleanup()
    //    }
    // }

    @objc func loadNextPage() {
        self.interactor?.loadNextPage()
    }

    @objc func sendAttachment(notification: NSNotification) {
        // Attachment size less base64 expansion and overhead.
        let maxInbandSize = Cache.tinode.getServerLimit(for: Tinode.kMaxMessageSize, withDefault: MessageViewController.kMaxInbandAttachmentSize) * 3 / 4 - 1024
        switch notification.object {
        case let content as FilePreviewContent:
            if content.data.count > maxInbandSize {
                self.interactor?.uploadFile(UploadDef(filename: content.fileName, mimeType: content.contentType, data: content.data))
            } else {
                _ = interactor?.sendMessage(content: Drafty().attachFile(mime: content.contentType, bits: content.data, fname: content.fileName))
            }
        case let content as ImagePreviewContent:
            guard case let ImagePreviewContent.ImageContent.uiimage(image) = content.imgContent else { return }

            guard let data = image.pixelData(forMimeType: content.contentType) else { return }
            print("image size: \(data.count), max inband size: \(maxInbandSize)")
            if data.count > maxInbandSize {
                self.interactor?.uploadImage(UploadDef(caption: content.caption, filename: content.fileName, mimeType: content.contentType, image: image, data: data, width: image.size.width * image.scale, height: image.size.height * image.scale))
            } else {
                let drafty = Drafty(plainText: " ").insertImage(at: 0, mime: content.contentType, bits: data, width: content.width!, height: content.height!, fname: content.fileName)
                if let caption = content.caption {
                    _ = drafty.appendLineBreak().append(Drafty(plainText: caption))
                }
                _ = interactor?.sendMessage(content: drafty)
            }
        default:
            break
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
        case "Messages2TopicInfo":
            let destinationVC = segue.destination as! TopicInfoViewController
            destinationVC.topicName = self.topicName ?? ""
        case "ShowImagePreview":
            let destinationVC = segue.destination as! ImagePreviewController
            destinationVC.previewContent = (sender as! ImagePreviewContent)
        case "ShowFilePreview":
            let destinationVC = segue.destination as! FilePreviewController
            destinationVC.previewContent = (sender as! FilePreviewContent)
        default:
            break
        }
    }

    @objc func navBarAvatarTapped(tapGestureRecognizer: UITapGestureRecognizer) {
        performSegue(withIdentifier: "Messages2TopicInfo", sender: nil)
    }

    private func setInterfaceColors() {
        if traitCollection.userInterfaceStyle == .dark {
            view.backgroundColor = .black
        } else {
            view.backgroundColor = .white
        }
    }
}

// Methods for updating title area and refreshing messages.
extension MessageViewController: MessageDisplayLogic {
    private func showInvitationDialog() {
        guard self.presentedViewController == nil else { return }
        let attrs = [ NSAttributedString.Key.font: UIFont.systemFont(ofSize: 20.0) ]
        let title = NSAttributedString(string: NSLocalizedString("New Chat", comment: "View title"), attributes: attrs)
        let alert = UIAlertController(
            title: nil,
            message: NSLocalizedString("You are invited to start a new chat. What would you like?", comment: "Call to action"),
            preferredStyle: .actionSheet)
        alert.setValue(title, forKey: "attributedTitle")
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Accept", comment: "Invite reaction button"), style: .default,
            handler: { action in
                self.interactor?.acceptInvitation()
        }))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Ignore", comment: "Invite reaction button"), style: .default,
            handler: { action in
                self.interactor?.ignoreInvitation()
        }))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Block", comment: "Invite reaction button"), style: .default,
            handler: { action in
                self.interactor?.blockTopic()
        }))
        self.present(alert, animated: true)
    }

    func switchTopic(topic: String?) {
        topicName = topic
    }

    func updateTitleBar(icon: UIImage?, title: String?, online: Bool?) {
        assert(Thread.isMainThread)
        self.navigationItem.title = title ?? NSLocalizedString("Undefined", comment: "Undefined chat name")

        navBarAvatarView.set(icon: icon, title: title, id: topicName, online: online)
        navBarAvatarView.bounds = CGRect(x: 0, y: 0, width: Constants.kNavBarAvatarSmallState, height: Constants.kNavBarAvatarSmallState)

        navBarAvatarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
                navBarAvatarView.heightAnchor.constraint(equalToConstant: Constants.kNavBarAvatarSmallState),
                navBarAvatarView.widthAnchor.constraint(equalTo: navBarAvatarView.heightAnchor)
            ])
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: navBarAvatarView)
    }

    func setOnline(online: Bool?) {
        assert(Thread.isMainThread)
        navBarAvatarView.setOnline(online: online)
    }

    func runTypingAnimation() {
        assert(Thread.isMainThread)
        navBarAvatarView.presentTypingAnimation(steps: 30)
    }

    func reloadAllMessages() {
        assert(Thread.isMainThread)
        collectionView.reloadSections(IndexSet(integer: 0))
    }

    func displayChatMessages(messages: [StoredMessage]) {
        assert(Thread.isMainThread)

        let oldData = self.messages
        let newData: [StoredMessage] = messages

        // Both empty: no change.
        guard !oldData.isEmpty || !newData.isEmpty else { return }

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

        // Update batch stats.
        let now = Date()
        let delta = newData.count - oldData.count
        if now.millisecondsSince1970 > self.lastMessageReceived.millisecondsSince1970 + Constants.kUpdateBatchTimeDeltaThresholdMs {
            self.updateBatchSize = delta
        } else {
            self.updateBatchSize += delta
        }
        self.lastMessageReceived = now

        if oldData.isEmpty || newData.isEmpty || self.updateBatchSize > Constants.kUpdateBatchFullRefreshThreshold {
            self.messages = newData
            collectionView.reloadSections(IndexSet(integer: 0))
            collectionView.layoutIfNeeded()
            collectionView.scrollToBottom()
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
            // The app will crash if the same index is marked as removed and refreshed. Which seems
            // to be an Apple bug because removed index is against the old array, refreshed against the new.
            refresh = Array(Set(refresh).subtracting(Set(diff.inserted)))

            collectionView.performBatchUpdates({ () -> Void in
                self.messages = newData
                if diff.removed.count > 0 {
                    collectionView.deleteItems(at: diff.removed.map { IndexPath(item: $0, section: 0) })
                }
                if diff.inserted.count > 0 {
                    collectionView.insertItems(at: diff.inserted.map { IndexPath(item: $0, section: 0) })
                }
            }, completion: nil)
            collectionView.performBatchUpdates({ () -> Void in
                self.collectionView.reloadItems(at: refresh.map { IndexPath(item: $0, section: 0) })
                self.collectionView.layoutIfNeeded()
                self.collectionView.scrollToBottom()
            }, completion: nil)
        }
    }

    func reloadMessages(fromSeqId loId: Int, toSeqId hiId: Int) {
        assert(Thread.isMainThread)
        let hiIdUpper = hiId + 1
        let rowIds = (loId..<hiIdUpper).map { self.messageSeqIdIndex[$0] }.filter { $0 != nil }
        self.collectionView.reloadItems(at: rowIds.map { IndexPath(item: $0!, section: 0) })
    }

    func updateProgress(forMsgId msgId: Int64, progress: Float) {
        assert(Thread.isMainThread)
        if let index = self.messageDbIdIndex[msgId],
            let cell = self.collectionView.cellForItem(at: IndexPath(row: index, section: 0)) as? MessageCell {
            cell.progressView.setProgress(progress)
        }
    }

    func applyTopicPermissions(withError err: Error? = nil) {
        assert(Thread.isMainThread)
        // Make sure the view is visible.
        guard self.isViewLoaded && ((self.view?.window) != nil) else { return }

        if !(self.topic?.isReader ?? false) || err != nil {
            self.collectionView.showNoAccessOverlay(withMessage: err?.localizedDescription)
        } else {
            self.collectionView.removeNoAccessOverlay()
        }
        // No "W" permission. Replace input field with a message "Not available".
        self.sendMessageBar.toggleNotAvailableOverlay(visible: !(self.topic?.isWriter ?? false) || err != nil)
        // The peer is missing either "W" or "R" permissions. Show "Peer's messaging is disabled" message.
        if let acs = self.topic?.peer?.acs, let missing = acs.missing {
            self.sendMessageBar.togglePeerMessagingDisabled(visible: acs.isJoiner(for: .want) && (missing.isReader || missing.isWriter))
        }
        // We are offered to join a chat.
        if let acs = self.topic?.accessMode, acs.isJoiner(for: Acs.Side.given) && (acs.excessive?.description.contains("RW") ?? false) {
            self.showInvitationDialog()
        }
    }

    func endRefresh() {
        assert(Thread.isMainThread)
        self.refreshControl.endRefreshing()
    }

    func dismissVC() {
        assert(Thread.isMainThread)
        self.navigationController?.popViewController(animated: true)
        self.dismiss(animated: true)
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

        cell.progressView.frame = attributes.progressViewFrame

        // Set colors and fill out content except for the avatar. The maxumum size is needed for placing attached images.
        configureCell(cell: cell, with: message, at: indexPath)

        cell.avatarView.frame = attributes.avatarFrame
        if attributes.avatarFrame != .zero  {
            // The avatar image should be assigned after setting the size. Otherwise it may be drawn twice.
            if let sub = topic?.getSubscription(for: message.from) {
                cell.avatarView.set(icon: sub.pub?.photo?.image(), title: sub.pub?.fn, id: message.from)
            } else {
                cell.avatarView.set(icon: nil, title: nil, id: message.from)
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

        return cell
    }

    private func configureCell(cell: MessageCell, with message: Message, at indexPath: IndexPath) {

        cell.seqId = message.seqId
        cell.isDeleted = message.isDeleted

        cell.content.backgroundColor = nil
        if message.isDeleted {
            if traitCollection.userInterfaceStyle == .dark {
                cell.containerView.backgroundColor = Constants.kDeletedMessageBubbleColorDark
            } else {
                cell.containerView.backgroundColor = Constants.kDeletedMessageBubbleColorLight
            }
            cell.content.textColor = Constants.kDeletedMessageTextColor
        } else if isFromCurrentSender(message: message) {
            if traitCollection.userInterfaceStyle == .dark {
                cell.containerView.backgroundColor = Constants.kOutgoingBubbleColorDark
                cell.content.textColor = Constants.kOutgoingTextColorDark
            } else {
                cell.containerView.backgroundColor = Constants.kOutgoingBubbleColorLight
                cell.content.textColor = Constants.kOutgoingTextColorDark
            }
        } else {
            if traitCollection.userInterfaceStyle == .dark {
                cell.containerView.backgroundColor = Constants.kIncomingBubbleColorDark
                cell.content.textColor = Constants.kIncomingTextColorDark
            } else {
                cell.containerView.backgroundColor = Constants.kIncomingBubbleColorLight
                cell.content.textColor = Constants.kIncomingTextColorLight
            }
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
        senderName = senderName ?? String(format: NSLocalizedString("Unknown %@", comment: "Sender with missing name"), message.from ?? "none")

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
            iconName = "in-progress-30"
        } else {
            if topic.msgReadCount(seq: message.seqId) > 0 {
                iconName = "done-all-30"
                tint = Constants.kDeliveryMarkerTint
            } else if topic.msgRecvCount(seq: message.seqId) > 0 {
                iconName = "done-all-30"
            } else {
                iconName = "done-30"
            }
        }

        return (UIImage(named: iconName)!, tint)
    }

    // Returns closure which adds message bubble mask to the supplied UIView.
    func bubbleDecorator(for message: Message, at indexPath: IndexPath) -> (UIView) -> Void {
        let isIncoming = !isFromCurrentSender(message: message)
        let isDeleted = message.isDeleted

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
            let path = !isDeleted ?
                MessageBubbleDecorator.draw(view.bounds, isIncoming: isIncoming, style: style) :
                MessageBubbleDecorator.drawDeleted(view.bounds)
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
        return (topic?.isGrpType ?? false) && !(topic?.isChannel ?? false) && !isFromCurrentSender(message: message)
    }

    // Show avatar in the given message
    func shouldShowAvatar(for message: Message, at indexPath: IndexPath) -> Bool {
        return avatarsVisible(message: message) && (!isNextMessageSameSender(at: indexPath) || !isNextMessageSameDate(at: indexPath))
    }

    // Should we show upload progress bar for reference attachment messages?
    func shouldShowProgressBar(for message: Message) -> Bool {
        return message.isPending && (message.content?.hasRefEntity ?? false)
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
        let isDeleted = message.isDeleted
        // This message has an avatar.
        let isAvatarVisible = !isDeleted && shouldShowAvatar(for: message, at: indexPath)

        // Insets for the message bubble relative to collectionView: bubble should not touch the sides of the screen.
        let containerPadding = isOutgoing ? Constants.kOutgoingContainerPadding : Constants.kIncomingContainerPadding

        // Size of the message bubble.
        let showUploadProgress = shouldShowProgressBar(for: message)
        let containerSize = calcContainerSize(for: message, avatarsVisible: hasAvatars, progressVisible: showUploadProgress)
        // Get cell size.
        let cellSize = !isDeleted ? calcCellSize(forItemAt: indexPath) : containerSize
        attr.cellSpacing = Constants.kVerticalCellSpacing

        // Height of the field with the current date above the first message of the day.
        let newDateLabelHeight = !isDeleted ? calcNewDateLabelHeight(at: indexPath) : 0

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

        // isDeleted ? center container : else
        // isFromCurrent Sender ? Flush container right : flush left.
        let originX =
            isDeleted ? (collectionView.bounds.width - containerSize.width) / 2 :
            isOutgoing ? cellSize.width - avatarPadding - containerSize.width - containerPadding.right : avatarPadding + containerPadding.left
        attr.containerFrame = CGRect(origin: CGPoint(x: originX, y: newDateLabelHeight + containerPadding.top), size: containerSize)

        // Content: RichTextLabel.
        let contentInset =
            isDeleted ? Constants.kDeletedMessageContentInset :
            isOutgoing ? Constants.kOutgoingMessageContentInset : Constants.kIncomingMessageContentInset
        attr.contentFrame = CGRect(x: contentInset.left, y: contentInset.top, width: attr.containerFrame.width - contentInset.left - contentInset.right, height: attr.containerFrame.height - contentInset.top - contentInset.bottom - (showUploadProgress ? Constants.kProgressViewHeight : 0))

        var rightEdge = CGPoint(x: attr.containerFrame.width - Constants.kDeliveryMarkerPadding, y: attr.containerFrame.height - Constants.kDeliveryMarkerSize)
        if isOutgoing {
            rightEdge.x -= Constants.kDeliveryMarkerSize
            attr.deliveryMarkerFrame = CGRect(x: rightEdge.x, y: rightEdge.y, width: Constants.kDeliveryMarkerSize, height: Constants.kDeliveryMarkerSize)
        } else {
            attr.deliveryMarkerFrame = .zero
        }

        attr.timestampFrame = !message.isDeleted ? CGRect(x: rightEdge.x - Constants.kTimestampWidth - Constants.kTimestampPadding, y: rightEdge.y, width: Constants.kTimestampWidth, height: Constants.kDeliveryMarkerSize) : .zero

        // New date label
        if newDateLabelHeight > 0 {
            attr.newDateFrame = CGRect(origin: CGPoint(x: 0, y: attr.containerFrame.minY - containerPadding.top - newDateLabelHeight), size: CGSize(width: cellSize.width, height: newDateLabelHeight))
        } else {
            attr.newDateFrame = .zero
        }

        if showUploadProgress {
            let origin = CGPoint(x: attr.contentFrame.origin.x, y: attr.contentFrame.origin.y + attr.contentFrame.size.height)
            attr.progressViewFrame =
                CGRect(origin: origin, size: CGSize(width: attr.contentFrame.width, height: Constants.kProgressViewHeight))
        } else {
            attr.progressViewFrame = .zero
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
        let showProgress = shouldShowProgressBar(for: message)
        let containerHeight = calcContainerSize(for: message, avatarsVisible: hasAvatars, progressVisible: showProgress).height
        let size = CGSize(width: calcCellWidth(), height: calcCellHeightFromContent(for: message, at: indexPath, containerHeight: containerHeight, avatarsVisible: hasAvatars, progressVisible: showProgress))
        // cellSizeCache[indexPath.item] = size
        return size
    }

    func calcCellWidth() -> CGFloat {
        return collectionView.frame.width - collectionView.layoutMargins.left - collectionView.layoutMargins.right
    }

    func calcCellHeightFromContent(
        for message: Message, at indexPath: IndexPath, containerHeight: CGFloat,
        avatarsVisible hasAvatars: Bool, progressVisible: Bool) -> CGFloat {

        let senderNameLabelHeight: CGFloat = shouldShowAvatar(for: message, at: indexPath) ? Constants.kSenderNameLabelHeight : 0
        let newDateLabelHeight: CGFloat = calcNewDateLabelHeight(at: indexPath)
        let avatarHeight = hasAvatars ? Constants.kAvatarSize : 0

        let totalLabelHeight: CGFloat = newDateLabelHeight + containerHeight + senderNameLabelHeight + (progressVisible ? Constants.kProgressViewHeight : 0)
        return max(avatarHeight, totalLabelHeight)
    }

    func calcNewDateLabelHeight(at indexPath: IndexPath) -> CGFloat {
        let height: CGFloat
        if isNewDateLabelVisible(at: indexPath) {
            height = Constants.kNewDateLabelHeight
        } else if !(topic?.isGrpType ?? false) && !isPreviousMessageSameSender(at: indexPath) {
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
    func calcContainerSize(for message: Message, avatarsVisible: Bool, progressVisible: Bool) -> CGSize {
        let maxWidth = calcMaxContentWidth(for: message, avatarsVisible: avatarsVisible)
        let insets =
            message.isDeleted ? Constants.kDeletedMessageContentInset :
            isFromCurrentSender(message: message) ? Constants.kOutgoingMessageContentInset : Constants.kIncomingMessageContentInset

        var size = calcContentSize(for: message, maxWidth: maxWidth)

        size.width += insets.left + insets.right
        size.width = max(size.width, Constants.kMinimumCellWidth)
        size.height += insets.top + insets.bottom
        if progressVisible {
            size.height += Constants.kProgressViewHeight
        }

        return size
    }

    /// Calculate size of message content.
    func calcContentSize(for message: Message, maxWidth: CGFloat) -> CGSize {
        let attributedText = NSMutableAttributedString()

        let carveout = isFromCurrentSender(message: message) ? Constants.kOutgoingMetadataCarveout : Constants.kIncomingMetadataCarveout

        let textColor: UIColor
        if message.isDeleted {
            textColor = Constants.kDeletedMessageTextColor
        } else if traitCollection.userInterfaceStyle == .dark {
            textColor = isFromCurrentSender(message: message) ? Constants.kOutgoingTextColorDark : Constants.kIncomingTextColorDark
        } else {
            textColor = isFromCurrentSender(message: message) ? Constants.kOutgoingTextColorLight : Constants.kIncomingTextColorLight
        }

        let storedMessage = message as! StoredMessage
        if let content = storedMessage.attributedContent(fitIn: CGSize(width: maxWidth, height: collectionView.frame.height * 0.66), withDefaultAttributes: [.font: Constants.kContentFont, .foregroundColor: textColor]) {
            attributedText.append(content)
        } else {
            attributedText.append(NSAttributedString(string: "none", attributes: [.font: Constants.kContentFont]))
        }
        attributedText.append(NSAttributedString(string: carveout, attributes: [.font: Constants.kContentFont]))

        // FIXME: storedMessage may contain an image surrounded by text. In such cases,
        // size calculations may be wrong. Handle it.
        return storedMessage.isImage ?
            attributedText.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                                        context: nil).integral.size :
            textSizeHelper.computeSize(for: attributedText, within: maxWidth)
    }
}

// Methods for handling taps in messages.

extension MessageViewController : MessageCellDelegate {
    func didLongTap(in cell: MessageCell) {
        createPopupMenu(in: cell)
    }

    func didTapContent(in cell: MessageCell, url: URL?) {
        guard let url = url else { return }

        if url.scheme == "tinode" {
            switch url.path {
            case "/post":
                handleButtonPost(in: cell, using: url)
            case "/small-attachment":
                handleSmallAttachment(in: cell, using: url)
                Cache.log.debug("MessageViewController - small attachment: %@", url.description)
            case "/large-attachment":
                handleLargeAttachment(in: cell, using: url)
                Cache.log.debug("MessageViewController - large attachment: %@", url.description)
            case "/preview-image":
                showImagePreview(in: cell)
            default:
                Cache.log.error("MessageVC - unknown tinode:// action: %@", url.path)
                break
            }
            return
        }

        UIApplication.shared.open(url)
    }

    // TODO: remove as unused
    func didTapMessage(in cell: MessageCell) {}

    // TODO: remove as unused or go to user's profile (p2p topic?)
    func didTapAvatar(in cell: MessageCell) {}

    func createPopupMenu(in cell: MessageCell) {
        guard !cell.isDeleted else { return }

        // Make cell the first responder otherwise menu will show wrong items.
        if sendMessageBar.inputField.isFirstResponder {
            sendMessageBar.inputField.nextResponderOverride = cell
        } else {
            cell.becomeFirstResponder()
        }

        // Set up the shared UIMenuController
        var menuItems: [MessageMenuItem] = []
        menuItems.append(MessageMenuItem(title: NSLocalizedString("Copy", comment: "Menu item"), action: #selector(copyMessageContent(sender:)), seqId: cell.seqId))
        if !(topic?.isChannel ?? true) {
            // Channel users cannot delete messages.
            menuItems.append(MessageMenuItem(title: NSLocalizedString("Delete", comment: "Menu item"), action: #selector(deleteMessage(sender:)), seqId: cell.seqId))
        }
        UIMenuController.shared.menuItems = menuItems

        // Tell the menu controller the first responder's frame and its super view
        UIMenuController.shared.setTargetRect(cell.content.frame, in: cell.containerView)

        // Animate the menu onto view
        UIMenuController.shared.setMenuVisible(true, animated: true)

        // Capture menu dismissal
        NotificationCenter.default.addObserver(self, selector: #selector(willHidePopupMenu), name: UIMenuController.willHideMenuNotification, object: nil)
    }

    @objc func willHidePopupMenu() {
        if sendMessageBar.inputField.nextResponderOverride != nil {
            sendMessageBar.inputField.nextResponderOverride!.resignFirstResponder()
            sendMessageBar.inputField.nextResponderOverride = nil
        }

        UIMenuController.shared.menuItems = nil
        NotificationCenter.default.removeObserver(self, name: UIMenuController.willHideMenuNotification, object: nil)
    }

    @objc func copyMessageContent(sender: UIMenuController) {
        guard let menuItem = sender.menuItems?.first as? MessageMenuItem, menuItem.seqId > 0, let msgIndex = messageSeqIdIndex[menuItem.seqId] else { return }

        let msg = messages[msgIndex]

        var senderName: String?
        if let sub = topic?.getSubscription(for: msg.from), let pub = sub.pub {
            senderName = pub.fn
        }
        senderName = senderName ?? String(format: NSLocalizedString("Unknown %@", comment: ""), msg.from ?? "none")
        UIPasteboard.general.string = "[\(senderName!)]: \(msg.content?.string ?? ""); \(RelativeDateFormatter.shared.shortDate(from: msg.ts))"
    }

    @objc func deleteMessage(sender: UIMenuController) {
        guard let menuItem = sender.menuItems?.first as? MessageMenuItem, menuItem.seqId > 0 else { return }
        interactor?.deleteMessage(seqId: menuItem.seqId)
    }

    func didTapOutsideContent(in cell: MessageCell) {
        _ = self.sendMessageBar.inputField.resignFirstResponder()
    }

    func didTapCancelUpload(in cell: MessageCell) {
        guard let topicId = self.topicName,
            let msgIdx = self.messageSeqIdIndex[cell.seqId] else { return }
        _ = Cache.getLargeFileHelper().cancelUpload(topicId: topicId, msgId: self.messages[msgIdx].msgId)
    }

    private func handleButtonPost(in cell: MessageCell, using url: URL) {
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String : String]?
        if let queryItems = parts?.queryItems {
            query = [:]
            for item in queryItems {
                query![item.name] = item.value
            }
        }
        let newMsg = Drafty(content: query?["title"] ?? NSLocalizedString("undefined", comment: "Button with missing text"))
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
        guard var urlComps = URLComponents(string: downloadFrom) else { return }
        if let filename = url.extractQueryParam(named: "filename") {
            urlComps.queryItems = [URLQueryItem(name: "origfn", value: filename)]
        }
        if let targetUrl = urlComps.url, targetUrl.scheme == "http" || targetUrl.scheme == "https" {
            Cache.getLargeFileHelper().startDownload(from: targetUrl)
        }
    }

    private func handleSmallAttachment(in cell: MessageCell, using url: URL) {
        // TODO: move logic to MessageInteractor.
        guard let data = MessageViewController.extractAttachment(from: cell), !data.isEmpty else { return }
        let d = data[0]
        // FIXME: use actual mime instead of nil when generating file name.
        let filename = url.extractQueryParam(named: "filename") ?? Utils.uniqueFilename(forMime: nil)
        let documentsUrl: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsUrl.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: documentsUrl, withIntermediateDirectories: true, attributes: nil)
            try d.write(to: destinationURL)
            UiUtils.presentFileSharingVC(for: destinationURL)
        } catch {
            Cache.log.error("MessageVC - save attachment failed: %@", error.localizedDescription)
        }
    }

    private func showImagePreview(in cell: MessageCell) {
        // TODO: maybe pass nil to show "broken image" preview instead of returning.
        guard let index = messageSeqIdIndex[cell.seqId] else { return }
        let msg = messages[index]
        guard let entity = msg.content?.entities?[0], let bits = entity.data?["val"]?.asData() else { return }

        let content = ImagePreviewContent(
            imgContent: ImagePreviewContent.ImageContent.rawdata(bits),
            caption: nil,
            fileName: entity.data?["name"]?.asString(),
            contentType: entity.data?["mime"]?.asString(),
            size: Int64(bits.count),
            width: entity.data?["width"]?.asInt(),
            height: entity.data?["height"]?.asInt())
        performSegue(withIdentifier: "ShowImagePreview", sender: content)
    }
}
