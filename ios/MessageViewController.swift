//
//  MessageViewController.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit

protocol MessageDisplayLogic: class {
    func displayChatMessages(messages: [StoredMessage])
}

class MessageViewController: UIViewController, MessageDisplayLogic {
    public var topicName: String?
    private var interactor: MessageBusinessLogic?

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
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if !(self.interactor?.setup(topicName: self.topicName) ?? false) {
            print("error in interactor setup for \(String(describing: self.topicName))")
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        self.interactor?.attachToTopic()
    }
    override func viewDidDisappear(_ animated: Bool) {
        self.interactor?.cleanup()
    }
}

extension MessageViewController {
    func displayChatMessages(messages: [StoredMessage]) {
        // todo
        print("messages count = \(messages.count)")
    }
}
