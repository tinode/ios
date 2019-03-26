//
//  ViewController.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import UIKit
import MessageKit
import TinodeSDK

protocol ChatListDisplayLogic: class {
    func displayChats(_ topics: [DefaultComTopic])
    func displayLoginView()
}

class ChatListViewController: UITableViewController, ChatListDisplayLogic {


    var interactor: ChatListBusinessLogic?
    var topics: [DefaultComTopic] = []
    var router: ChatListRoutingLogic?

    private func setup() {
        let viewController = self
        let interactor = ChatListInteractor()
        let presenter = ChatListPresenter()
        let router = ChatListRouter()

        viewController.interactor = interactor
        viewController.router = router
        interactor.presenter = presenter
        interactor.router = router
        presenter.viewController = viewController
        router.viewController = viewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        setup()
        self.interactor?.attachToMeTopic()
    }
    override func viewDidAppear(_ animated: Bool) {
        self.interactor?.loadAndPresentTopics()
    }
    func displayLoginView() {
        DispatchQueue.main.async {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let destinationVC = storyboard.instantiateViewController(withIdentifier: "StartNavigator") as! UINavigationController
            self.show(destinationVC, sender: nil)
        }
    }
    func displayChats(_ topics: [DefaultComTopic]) {
        self.topics = topics
        DispatchQueue.main.async {
            self.tableView!.reloadData()
        }
    }
}

extension ChatListViewController {
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "Chats2Messages" {
            router?.routeToChat(segue: segue)
        }
    }
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return topics.count
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatsTableViewCell") as! ChatListTableViewCell
        let topic = self.topics[indexPath.row]
        cell.name.text = topic.pub?.fn ?? "Unknown or unnamed"
        cell.name.sizeToFit()
        if let b64data = topic.pub?.photo?.data,
            let dataDecoded = Data(base64Encoded: b64data, options: .ignoreUnknownCharacters) {
            let decodedImage = UIImage(data: dataDecoded)
            let a = Avatar(image: decodedImage, initials: "")
            cell.icon.set(avatar: a)
        }
        return cell
    }
}
