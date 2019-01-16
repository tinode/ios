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

protocol MessageDisplayLogic: class {
    func displayChatMessages(messages: [StoredMessage])
}

class MessageViewController: MessageKit.MessagesViewController, MessageDisplayLogic {
    public var topicName: String?
    var messages: [MessageType] = []
    private var interactor: (MessageBusinessLogic & MessageDataStore)?

    init() {
        super.init(nibName: nil, bundle: nil)
        self.setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setup()
    }

    private func setup() {
        let interactor = MessageInteractor()
        let presenter = MessagePresenter()
        interactor.presenter = presenter
        presenter.viewController = self

        self.interactor = interactor
        
        messagesCollectionView.messagesDataSource = self
        messagesCollectionView.messagesLayoutDelegate = self
        messagesCollectionView.messagesDisplayDelegate = self
        messageInputBar.delegate = self
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if !(self.interactor?.setup(topicName: self.topicName) ?? false) {
            print("error in interactor setup for \(String(describing: self.topicName))")
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        self.interactor?.attachToTopic()
        self.interactor?.loadMessages()
    }
    override func viewDidDisappear(_ animated: Bool) {
        self.interactor?.cleanup()
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
    
    func displayChatMessages(messages: [StoredMessage]) {
        self.messages = messages
        self.messagesCollectionView.reloadData()
    }
}

extension MessageViewController: MessagesDataSource {
    func currentSender() -> Sender {
        return Sender(id: Cache.getTinode().myUid ?? "???", displayName: "??")
    }
    func numberOfSections(in messagesCollectionView: MessagesCollectionView) -> Int {
        return messages.count
    }
    func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
        return messages[indexPath.section]
    }
}

extension MessageViewController: MessagesDisplayDelegate, MessagesLayoutDelegate {}

extension MessageViewController: MessageInputBarDelegate {
    func messageInputBar(_ inputBar: MessageInputBar, didPressSendButtonWith text: String) {
        interactor?.sendMessage(content: text)
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
