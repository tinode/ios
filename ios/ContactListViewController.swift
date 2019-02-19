//
//  ContactListViewController.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

protocol ContactListDisplayLogic: class {
    func displayContacts(contacts: [ContactHolder])
}

class ContactListViewController: UITableViewController, ContactListDisplayLogic {
    var interactor: ContactListBusinessLogic?
    var contacts: [ContactHolder] = []
    var router: ContactListRoutingLogic?

    private func setup() {
        let viewController = self
        let interactor = ContactListInteractor()
        let presenter = ContactListPresenter()
        let router = ContactListRouter()
        
        viewController.interactor = interactor
        viewController.router = router
        interactor.presenter = presenter
        interactor.router = router
        presenter.viewController = viewController
        router.viewController = viewController
    }

    func displayContacts(contacts newContacts: [ContactHolder]) {
        self.contacts = newContacts
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setup()
    }
    override func viewDidAppear(_ animated: Bool) {
        self.interactor?.loadAndPresentContacts()
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.contacts.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ContactsTableViewCell", for: indexPath)

        // Configure the cell...
        let contact = contacts[indexPath.row]
        cell.textLabel?.text = contact.displayName
        cell.detailTextLabel?.text = contact.ims?.count ?? 0 > 0 ? contact.ims![0] : nil

        return cell
    }
}
