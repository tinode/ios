//
//  FindViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import MessageUI

protocol FindDisplayLogic: class {
    func displayLocalContacts(contacts: [ContactHolder])
    func displayRemoteContacts(contacts: [ContactHolder])
}

class FindViewController: UITableViewController, FindDisplayLogic {
    @IBOutlet weak var inviteActionButtonItem: UIBarButtonItem!
    var interactor: FindBusinessLogic?
    var localContacts: [ContactHolder] = []
    var remoteContacts: [ContactHolder] = []
    // var router: FindRoutingLogic?
    var searchController: UISearchController!
    var pendingSearchRequest: DispatchWorkItem? = nil

    private func setup() {
        let viewController = self
        let interactor = FindInteractor()
        let presenter = FindPresenter()
        // let router = FindRouter()

        viewController.interactor = interactor
        //viewController.router = router
        interactor.presenter = presenter
        // interactor.router = router
        presenter.viewController = viewController
        // router.viewController = viewController

        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.placeholder = "Search by tags"

        // Make it a-la Telegram UI instead of placing the search bar
        // in the navigation item.
        self.tableView.tableHeaderView = searchController.searchBar
        self.tableView.register(UINib(nibName: "ContactViewCell", bundle: nil), forCellReuseIdentifier: "ContactViewCell")

        searchController.delegate = self
        // The default is true.
        searchController.dimsBackgroundDuringPresentation = false
        // Monitor when the search button is tapped.
        searchController.searchBar.delegate = self
        self.definesPresentationContext = true
    }

    func displayLocalContacts(contacts newContacts: [ContactHolder]) {
        DispatchQueue.main.async {
            self.localContacts = newContacts
            self.tableView.reloadData()
        }
    }
    func displayRemoteContacts(contacts newContacts: [ContactHolder]) {
        DispatchQueue.main.async {
            self.remoteContacts = newContacts
            self.tableView.reloadData()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setup()
    }
    override func viewDidAppear(_ animated: Bool) {
        self.interactor?.setup()
        self.interactor?.attachToFndTopic()
        self.interactor?.loadAndPresentContacts(searchQuery: nil)
        self.tabBarController?.navigationItem.rightBarButtonItem = inviteActionButtonItem
    }
    override func viewDidDisappear(_ animated: Bool) {
        self.interactor?.cleanup()
        self.tabBarController?.navigationItem.rightBarButtonItem = nil
    }

    @IBAction func inviteActionClicked(_ sender: Any) {
        let inviteSubject = "Check out Tindroid Messenger"
        let inviteBody = "Check out Tindroid Messenger. Download it from https://github.com/tinode/"
        let attrs = [ NSAttributedString.Key.font: UIFont.systemFont(ofSize: 20.0) ]
        let dialogTitle = NSAttributedString(string: "Invite", attributes: attrs)
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.setValue(dialogTitle, forKey: "attributedTitle")
        alert.addAction(UIAlertAction(title: "Copy to clipboard", style: .default, handler: { action in
            let pasteboard = UIPasteboard.general
            pasteboard.string = inviteBody
        }))
        alert.addAction(UIAlertAction(title: "Email", style: .default, handler: { action in
            if MFMailComposeViewController.canSendMail() {
                let mailVC = MFMailComposeViewController()
                mailVC.mailComposeDelegate = self
                mailVC.setSubject(inviteSubject)
                mailVC.setMessageBody(inviteBody, isHTML: false)

                self.present(mailVC, animated: true)
            } else {
                UiUtils.showToast(message: "No access to email")
            }
        }))
        alert.addAction(UIAlertAction(title: "Messages", style: .default, handler: { action in
            if MFMessageComposeViewController.canSendText() {
                let messageVC = MFMessageComposeViewController()
                messageVC.messageComposeDelegate = self
                messageVC.body = inviteBody

                self.present(messageVC, animated: true)
            } else {
                UiUtils.showToast(message: "No access to messages")
            }
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return localContacts.isEmpty ? 1 : localContacts.count
        case 1: return remoteContacts.isEmpty ? 1 : remoteContacts.count
        default: return 0
        }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Local Contacts"
        case 1: return "Directory"
        default: return nil
        }
    }

    override func tableView(_: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 40.0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isSectionEmpty(section: indexPath.section) {
            return tableView.dequeueReusableCell(withIdentifier: "FindTableViewCellEmpty", for: indexPath)
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ContactViewCell", for: indexPath) as! ContactViewCell
            cell.delegate = self

            // Configure the cell...
            let contact = indexPath.section == 0 ? localContacts[indexPath.row] : remoteContacts[indexPath.row]
            cell.avatar.set(icon: contact.image, title: contact.displayName, id: contact.uniqueId)
            cell.title.text = contact.displayName
            cell.title.sizeToFit()
            cell.subtitle.text = contact.subtitle ?? contact.uniqueId
            cell.subtitle.sizeToFit()

            return cell
        }
    }

    private func isSectionEmpty(section: Int) -> Bool {
        switch section {
        case 0: return localContacts.isEmpty
        case 1: return remoteContacts.isEmpty
        default: return true
        }
    }

    func getUniqueId(for path: IndexPath) -> String? {
        switch path.section {
        case 0: return self.localContacts[path.row].uniqueId
        case 1: return self.remoteContacts[path.row].uniqueId
        default: return nil
        }
    }
}

// MARK: - Search functionality

extension FindViewController: UISearchResultsUpdating, UISearchControllerDelegate, UISearchBarDelegate {

    private func doSearch(queryString: String?) {
        //print("Searching contacts for: \(queryString)")
        self.interactor?.loadAndPresentContacts(searchQuery: queryString)
    }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        pendingSearchRequest?.cancel()
        pendingSearchRequest = nil
        guard let s = getQueryString() else { return }
        doSearch(queryString: s)
    }
    private func getQueryString() -> String? {
        let whitespaceCharacterSet = CharacterSet.whitespaces
        let queryString =
            searchController.searchBar.text!.trimmingCharacters(in: whitespaceCharacterSet)
        return !queryString.isEmpty ? queryString : nil
    }
    func updateSearchResults(for searchController: UISearchController) {
        pendingSearchRequest?.cancel()
        pendingSearchRequest = nil
        let queryString = getQueryString()
        let currentSearchRequest = DispatchWorkItem() {
            self.doSearch(queryString: queryString)
        }
        pendingSearchRequest = currentSearchRequest
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: currentSearchRequest)
    }
    func didDismissSearchController(_ searchController: UISearchController) {
        pendingSearchRequest?.cancel()
        pendingSearchRequest = nil
        self.interactor?.loadAndPresentContacts(searchQuery: nil)
    }
}

extension FindViewController: ContactViewCellDelegate {
    func selected(from cell: UITableViewCell) {
        guard let indexPath = tableView.indexPathForSelectedRow else { return }
        guard let id = getUniqueId(for: indexPath) else { return }

        // If the search bar is active, deactivate it.
        if searchController.isActive {
            // Disable the animation as we are going straight to another view
            UIView.performWithoutAnimation {
                searchController.isActive = false
            }
        }

        // Have to do it with a delay because it takes time to dismiss searchController and
        // navbar won't swap controllers while in transition:
        // pushViewController:animated: called on <UINavigationController 0x7ff2cf80e400> while an existing transition or presentation is occurring; the navigation stack will not be updated.
        presentChatReplacingCurrentVC(with: id, afterDelay: .milliseconds(30))
    }
}

extension FindViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}

extension FindViewController: MFMessageComposeViewControllerDelegate {
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
    }
}
