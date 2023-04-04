//
//  MessageViewController+MessageDisplayLogic.swift
//  Tinodios
//
//  Copyright © 2023 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

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
            handler: { _ in
                self.interactor?.acceptInvitation()
        }))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Ignore", comment: "Invite reaction button"), style: .default,
            handler: { _ in
                self.interactor?.ignoreInvitation()
        }))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Block", comment: "Invite reaction button"), style: .default,
            handler: { _ in
                self.interactor?.blockTopic()
        }))
        self.present(alert, animated: true)
    }

    func switchTopic(topic: String?) {
        topicName = topic
    }

    func updateTitleBar(pub: TheCard?, online: Bool?, deleted: Bool) {
        assert(Thread.isMainThread)
        self.navigationItem.title = pub?.fn ?? NSLocalizedString("Undefined", comment: "Undefined chat name")
        navBarAvatarView.set(pub: pub, id: topicName, online: online, deleted: deleted)
        navBarAvatarView.bounds = CGRect(x: 0, y: 0, width: Constants.kNavBarAvatarSmallState, height: Constants.kNavBarAvatarSmallState)

        navBarAvatarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
                navBarAvatarView.heightAnchor.constraint(equalToConstant: Constants.kNavBarAvatarSmallState),
                navBarAvatarView.widthAnchor.constraint(equalTo: navBarAvatarView.heightAnchor)
            ])
        var items = [UIBarButtonItem(customView: navBarAvatarView)]
        let webrtc = Cache.tinode.getServerParam(for: "iceServers") != nil
        if let t = self.topic, t.isP2PType, webrtc {
            items.append(self.navBarCallBtn)
        }
        self.navigationItem.setRightBarButtonItems(items, animated: false)
    }

    func displayPinnedMessages(pins: [Int], selected: Int) {
        assert(Thread.isMainThread)
        guard collectionView != nil else { return }

        self.pinnedMessageSeqs = pins
        if selected >= 0 && selected < pins.count {
            self.pinnedSelectionIndex = selected
        }
        collectionView.reloadSections(IndexSet(integer: 0))
        collectionView.layoutIfNeeded()
    }

    func setOnline(online: Bool?) {
        assert(Thread.isMainThread)
        navBarAvatarView.online = online
    }

    func runTypingAnimation() {
        assert(Thread.isMainThread)
        navBarAvatarView.presentTypingAnimation(steps: 30)
    }

    func reloadAllMessages() {
        assert(Thread.isMainThread)
        collectionView.reloadSections(IndexSet(integer: 0))
    }

    func displayChatMessages(messages: [StoredMessage], _ scrollToMostRecentMessage: Bool) {
        assert(Thread.isMainThread)
        guard collectionView != nil else { return }
        let oldData = self.messages
        let newData: [StoredMessage] = messages

        // Both empty: no change.
        guard !oldData.isEmpty || !newData.isEmpty else { return }

        self.messageSeqIdIndex = newData.enumerated().reduce([Int: Int]()) { (dict, item) -> [Int: Int] in
            var dict = dict
            dict[item.element.seqId] = item.offset
            return dict
        }
        self.messageDbIdIndex = newData.enumerated().reduce([Int64: Int]()) { (dict, item) -> [Int64: Int] in
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
            if scrollToMostRecentMessage {
                collectionView.scrollToBottom()
            }
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

            if !diff.inserted.isEmpty || !diff.removed.isEmpty {
                collectionView.performBatchUpdates({ () -> Void in
                    self.messages = newData
                    if diff.removed.count > 0 {
                        collectionView.deleteItems(at: diff.removed.map { IndexPath(item: $0, section: 0) })
                    }
                    if diff.inserted.count > 0 {
                        collectionView.insertItems(at: diff.inserted.map { IndexPath(item: $0, section: 0) })
                    }
                }, completion: nil)
            }
            if !refresh.isEmpty {
                collectionView.performBatchUpdates({ () -> Void in
                    self.messages = newData
                    self.collectionView.reloadItems(at: refresh.map { IndexPath(item: $0, section: 0) })
                    self.collectionView.layoutIfNeeded()
                    if scrollToMostRecentMessage {
                        self.collectionView.scrollToBottom()
                    }
                }, completion: nil)
            }
        }
    }

    func reloadMessages(fromSeqId loId: Int, toSeqId hiId: Int) {
        assert(Thread.isMainThread)
        guard self.collectionView != nil else { return }
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

        let publishingForbidden = !(self.topic?.isWriter ?? false) || err != nil
        // No "W" permission. Replace input field with a message "Not available".
        self.sendMessageBar.toggleNotAvailableOverlay(visible: publishingForbidden)
        if publishingForbidden {
            // Dismiss all pending messages.
            self.togglePreviewBar(with: nil)
            self.interactor?.dismissPendingMessage()
        }
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

    func togglePreviewBar(with preview: NSAttributedString?, onAction action: PendingPreviewAction = .none) {
        if preview == nil {
            isForwardingMessage = false
        }
        if isForwardingMessage {
            self.forwardMessageBar.togglePendingPreviewBar(with: preview)
        } else {
            self.sendMessageBar.togglePendingPreviewBar(withMessage: preview, onAction: action)
        }
        self.reloadInputViews()
    }
}
