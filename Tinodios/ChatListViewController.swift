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
    func updateChat(_ name: String)
}

class ChatListViewController: UITableViewController, ChatListDisplayLogic {

    var interactor: ChatListBusinessLogic?
    var topics: [DefaultComTopic] = []
    // Index of contacts: name => position in topics
    var rowIndex: Dictionary<String, Int> = Dictionary()
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
        self.rowIndex.removeAll()
        var i = 0
        for topic in topics {
            rowIndex[topic.name] = i
            i += 1
        }
        DispatchQueue.main.async {
            self.tableView!.reloadData()
        }
    }

    func updateChat(_ name: String) {
        guard let position = rowIndex[name] else { return }
        DispatchQueue.main.async {
            self.tableView!.reloadRows(at: [IndexPath(item: position, section: 0)], with: .automatic)
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
        cell.title.text = topic.pub?.fn ?? "Unknown or unnamed"
        cell.title.sizeToFit()
        cell.subtitle.text = topic.comment
        cell.subtitle.sizeToFit()
        let unread = topic.unread
        if unread > 0 {
            cell.unreadCount.text = unread > 9 ? "9+" : String(unread)
            cell.unreadCount.isHidden = false
        } else {
            cell.unreadCount.isHidden = true
        }

        // Online/offline indicator
        cell.online.backgroundColor = topic.online ?
            UIColor.init(red: 0x40/255, green: 0xC0/255, blue: 0x40/255, alpha: 1.0) :
            UIColor.init(red: 0xE0/255, green: 0xE0/255, blue: 0xE0/255, alpha: 1.0)

        // Avatar image
        if let b64data = topic.pub?.photo?.data,
            let dataDecoded = Data(base64Encoded: b64data, options: .ignoreUnknownCharacters) {
            let decodedImage = UIImage(data: dataDecoded)
            cell.icon.set(avatar: Avatar(image: decodedImage))
        } else {
            // Avatar placeholder.
            let firstChar = topic.pub?.fn ?? "?"
            let avatar = Avatar(initials: String(firstChar[firstChar.startIndex]).uppercased())
            cell.icon.set(avatar: avatar)
            cell.icon.placeholderFont = UIFont.preferredFont(forTextStyle: .title2)
            cell.icon.backgroundColor = ChatListViewController.selectBackground(id: topic.name)
        }
        return cell
    }

    static func selectBackground(id: String, dark: Bool = false) -> UIColor {
        let lightColors: [UIColor] = [
            UIColor.init(red: 0xef/255, green: 0x9a/255, blue: 0x9a/255, alpha: 1.0),
            UIColor.init(red: 0x90/255, green: 0xca/255, blue: 0xf9/255, alpha: 1.0),
            UIColor.init(red: 0xb0/255, green: 0xbe/255, blue: 0xc5/255, alpha: 1.0),
            UIColor.init(red: 0xb3/255, green: 0x9d/255, blue: 0xdb/255, alpha: 1.0),
            UIColor.init(red: 0xff/255, green: 0xab/255, blue: 0x91/255, alpha: 1.0),
            UIColor.init(red: 0xa5/255, green: 0xd6/255, blue: 0xa7/255, alpha: 1.0),
            UIColor.init(red: 0xdd/255, green: 0xdd/255, blue: 0xdd/255, alpha: 1.0),
            UIColor.init(red: 0xe6/255, green: 0xee/255, blue: 0x9c/255, alpha: 1.0),
            UIColor.init(red: 0xc5/255, green: 0xe1/255, blue: 0xa5/255, alpha: 1.0),
            UIColor.init(red: 0xff/255, green: 0xf5/255, blue: 0x9d/255, alpha: 1.0),
            UIColor.init(red: 0xf4/255, green: 0x8f/255, blue: 0xb1/255, alpha: 1.0),
            UIColor.init(red: 0x9f/255, green: 0xa8/255, blue: 0xda/255, alpha: 1.0),
            UIColor.init(red: 0xff/255, green: 0xe0/255, blue: 0x82/255, alpha: 1.0),
            UIColor.init(red: 0xbc/255, green: 0xaa/255, blue: 0xa4/255, alpha: 1.0),
            UIColor.init(red: 0x80/255, green: 0xde/255, blue: 0xea/255, alpha: 1.0),
            UIColor.init(red: 0xce/255, green: 0x93/255, blue: 0xd8/255, alpha: 1.0)
        ]
        let darkColors: [UIColor] = [
            UIColor.init(red: 0xC6/255, green: 0x28/255, blue: 0x28/255, alpha: 1.0),
            UIColor.init(red: 0xAD/255, green: 0x14/255, blue: 0x57/255, alpha: 1.0),
            UIColor.init(red: 0x6A/255, green: 0x1B/255, blue: 0x9A/255, alpha: 1.0),
            UIColor.init(red: 0x45/255, green: 0x27/255, blue: 0xA0/255, alpha: 1.0),
            UIColor.init(red: 0x28/255, green: 0x35/255, blue: 0x93/255, alpha: 1.0),
            UIColor.init(red: 0x15/255, green: 0x65/255, blue: 0xC0/255, alpha: 1.0),
            UIColor.init(red: 0x02/255, green: 0x77/255, blue: 0xBD/255, alpha: 1.0),
            UIColor.init(red: 0x00/255, green: 0x83/255, blue: 0x8F/255, alpha: 1.0),
            UIColor.init(red: 0x00/255, green: 0x69/255, blue: 0x5C/255, alpha: 1.0),
            UIColor.init(red: 0x2E/255, green: 0x7D/255, blue: 0x32/255, alpha: 1.0),
            UIColor.init(red: 0x55/255, green: 0x8B/255, blue: 0x2F/255, alpha: 1.0),
            UIColor.init(red: 0x9E/255, green: 0x9D/255, blue: 0x24/255, alpha: 1.0),
            UIColor.init(red: 0xF9/255, green: 0xA8/255, blue: 0x25/255, alpha: 1.0),
            UIColor.init(red: 0xFF/255, green: 0x8F/255, blue: 0x00/255, alpha: 1.0),
            UIColor.init(red: 0xEF/255, green: 0x6C/255, blue: 0x00/255, alpha: 1.0),
            UIColor.init(red: 0xD8/255, green: 0x43/255, blue: 0x15/255, alpha: 1.0)
        ]

        let hash = UInt(id.hashCode().magnitude)
        if dark {
            return darkColors[Int(hash % UInt(darkColors.count))]
        } else {
            return lightColors[Int(hash % UInt(lightColors.count))]
        }

    }
}

// These extensions are needed for selecting the color of avatar background
extension Character {
    var asciiValue: UInt32? {
        return String(self).unicodeScalars.filter{$0.isASCII}.first?.value
    }
}

extension String {
    // ASCII array to map the string
    var asciiArray: [UInt32] {
        return unicodeScalars.filter{$0.isASCII}.map{$0.value}
    }

    // hashCode produces output equal to the Java hash function.
    func hashCode() -> Int32 {
        var hash : Int32 = 0
        for i in self.asciiArray {
            hash = 31 &* hash &+ Int32(i) // Be aware of overflow operators,
        }
        return hash
    }
}
