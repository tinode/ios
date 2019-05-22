//
//  NewGroupViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

protocol NewGroupDisplayLogic: class {
    func displayContacts(contacts: [ContactHolder])
}

class NewGroupViewController: UIViewController, UITableViewDataSource, NewGroupDisplayLogic {
    @IBOutlet weak var saveButtonItem: UIBarButtonItem!
    @IBOutlet weak var selectGroupAvatar: UIButton!
    @IBOutlet weak var membersTableView: UITableView!
    private var contacts = [ContactHolder]()
    private var interactor: NewGroupBusinessLogic?

    private func setup() {
        let interactor = NewGroupInteractor()
        self.interactor = interactor
        interactor.presenter = self
    }
    override func viewDidLoad() {
        super.viewDidLoad()

        self.membersTableView.dataSource = self
        self.membersTableView.allowsMultipleSelection = true
        setup()
    }
    override func viewDidAppear(_ animated: Bool) {
        self.tabBarController?.navigationItem.rightBarButtonItem = saveButtonItem
        self.interactor?.loadAndPresentContacts()
    }
    override func viewDidDisappear(_ animated: Bool) {
        self.tabBarController?.navigationItem.rightBarButtonItem = nil
    }
    func displayContacts(contacts: [ContactHolder]) {
        self.contacts = contacts
        self.membersTableView.reloadData()
    }
    // MARK: - Table view data source
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contacts.count
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "NewGroupTableViewCell", for: indexPath)

        // Configure the cell...
        let contact = contacts[indexPath.row]
        cell.textLabel?.text = contact.displayName
        cell.detailTextLabel?.text = contact.uniqueId

        return cell
    }
}
