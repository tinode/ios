//
//  FindViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Contacts
import MessageUI
import UIKit

protocol FindDisplayLogic: AnyObject {
    func displayLocalContacts(contacts: [ContactHolder])
    func displayRemoteContacts(contacts: [RemoteContactHolder])
}

class FindViewController: UITableViewController, FindDisplayLogic {
    static let kLocalContactsSection = 0
    static let kRemoteContactsSection = 1

    @IBOutlet weak var inviteActionButtonItem: UIBarButtonItem!
    var interactor: FindBusinessLogic?
    var localContacts: [ContactHolder] = []
    var remoteContacts: [RemoteContactHolder] = []
    var searchController: UISearchController!
    var pendingSearchRequest: DispatchWorkItem?

    // Flag which indicates that the user is leaving the view.
    var transitioningOut: Bool = false

    private func addAppStateObservers() {
        // App state observers.
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.deviceRotated),
            name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    private func removeAppStateObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification,
            object: nil)
    }

    private func updateSearchBarPlaceholder(authStatus: CNAuthorizationStatus) {
        let placeholderText: String
        let placeholderFontSize: CGFloat
        if authStatus == .authorized {
            placeholderText = NSLocalizedString("Search by tags", comment: "Placeholder prompt")
            placeholderFontSize = 17
        } else {
            placeholderText = NSLocalizedString("Search functionality limited. Grant Contacts permission.", comment: "Error message when permissions are missing")
            placeholderFontSize = 10
        }
        searchController.searchBar.textField?.attributedPlaceholder =
            NSAttributedString(
                string: placeholderText,
                attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: placeholderFontSize),
                             NSAttributedString.Key.foregroundColor: UIColor.systemGray])
    }

    func createDependencies() -> (FindBusinessLogic, FindPresentationLogic) {
        return (FindInteractor(), FindPresenter())
    }

    private func setup() {
        let viewController = self
        var (interactor, presenter) = createDependencies()

        viewController.interactor = interactor
        interactor.presenter = presenter
        presenter.viewController = viewController

        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        ContactsSynchronizer.default.permissionsChangedCallback = { [weak self] authStatus in
            DispatchQueue.main.async {
                self?.updateSearchBarPlaceholder(authStatus: authStatus)
            }
        }

        // Make it a-la Telegram UI instead of placing the search bar
        // in the navigation item.
        self.tableView.tableHeaderView = searchController.searchBar
        self.tableView.register(UINib(nibName: "ContactViewCell", bundle: nil), forCellReuseIdentifier: "ContactViewCell")

        transitioningOut = false

        searchController.delegate = self
        // The default is true.
        searchController.obscuresBackgroundDuringPresentation = false
        // Monitor when the search button is tapped.
        searchController.searchBar.delegate = self
        self.definesPresentationContext = true

        if !Cache.isContactSynchronizerActive() {
            Cache.synchronizeContactsPeriodically()
        }
        self.updateSearchBarPlaceholder(authStatus: ContactsSynchronizer.default.authStatus)

        addAppStateObservers()
    }

    deinit {
        removeAppStateObservers()
    }

    func displayLocalContacts(contacts newContacts: [ContactHolder]) {
        assert(Thread.isMainThread)
        self.localContacts = newContacts
        self.tableView.reloadData()
    }

    func displayRemoteContacts(contacts newContacts: [RemoteContactHolder]) {
        assert(Thread.isMainThread)
        self.remoteContacts = newContacts
        self.tableView.reloadData()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setup()
    }

    private func scrollToTop() {
        if self.tableView.indexPathsForVisibleRows?.count ?? 0 > 0 {
            let topIndexPath = IndexPath(row: 0, section: 0)
            self.tableView.scrollToRow(at: topIndexPath, at: .top, animated: false)
        }
    }

    @objc
    func deviceRotated() {
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.interactor?.setup()
        self.interactor?.attachToFndTopic()
        self.interactor?.loadAndPresentContacts(searchQuery: nil)
        self.tabBarController?.navigationItem.rightBarButtonItem = inviteActionButtonItem
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.interactor?.cleanup()
        self.tabBarController?.navigationItem.rightBarButtonItem = nil
    }

    @IBAction func inviteActionClicked(_ sender: Any) {
        let inviteSubject = NSLocalizedString("Check out Tinode Messenger", comment: "Invitation subject")
        let inviteBody = NSLocalizedString("Check out Tinode Messenger: https://tinode.co/", comment: "Invitation body")
        let attrs = [ NSAttributedString.Key.font: UIFont.systemFont(ofSize: 20.0) ]
        let dialogTitle = NSAttributedString(string: NSLocalizedString("Invite", comment: "Dialog title: call to action"), attributes: attrs)
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.setValue(dialogTitle, forKey: "attributedTitle")
        alert.addAction(UIAlertAction(title: NSLocalizedString("Copy to clipboard", comment: "Alert action"), style: .default, handler: { _ in
            let pasteboard = UIPasteboard.general
            pasteboard.string = inviteBody
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Email", comment: "Alert action"), style: .default, handler: { _ in
            if MFMailComposeViewController.canSendMail() {
                let mailVC = MFMailComposeViewController()
                mailVC.mailComposeDelegate = self
                mailVC.setSubject(inviteSubject)
                mailVC.setMessageBody(inviteBody, isHTML: false)

                self.present(mailVC, animated: true)
            } else {
                UiUtils.showToast(message: NSLocalizedString("No access to email", comment: "Error message"))
            }
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Messages", comment: "Alert action"), style: .default, handler: { _ in
            if MFMessageComposeViewController.canSendText() {
                let messageVC = MFMessageComposeViewController()
                messageVC.messageComposeDelegate = self
                messageVC.body = inviteBody

                self.present(messageVC, animated: true)
            } else {
                UiUtils.showToast(message: NSLocalizedString("No access to messages", comment: "Toast error message"))
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
        case FindViewController.kLocalContactsSection: return localContacts.isEmpty ? 1 : localContacts.count
        case FindViewController.kRemoteContactsSection: return remoteContacts.isEmpty ? 1 : remoteContacts.count
        default: return 0
        }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case FindViewController.kLocalContactsSection: return NSLocalizedString("Local Contacts", comment: "Section title")
        case FindViewController.kRemoteContactsSection: return NSLocalizedString("Directory", comment: "Section title")
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
            let contact = indexPath.section == FindViewController.kLocalContactsSection ? localContacts[indexPath.row] : remoteContacts[indexPath.row]
            cell.avatar.set(pub: contact.pub, id: contact.uniqueId, deleted: false)
            cell.title.text = contact.pub?.fn
            cell.title.sizeToFit()
            cell.subtitle.text = contact.subtitle ?? contact.uniqueId
            cell.subtitle.sizeToFit()

            return cell
        }
    }

    private func isSectionEmpty(section: Int) -> Bool {
        switch section {
        case FindViewController.kLocalContactsSection: return localContacts.isEmpty
        case FindViewController.kRemoteContactsSection: return remoteContacts.isEmpty
        default: return true
        }
    }

    func getUniqueId(for path: IndexPath) -> String? {
        switch path.section {
        case FindViewController.kLocalContactsSection: return self.localContacts[path.row].uniqueId
        case FindViewController.kRemoteContactsSection: return self.remoteContacts[path.row].uniqueId
        default: return nil
        }
    }

    // Opens a chat with the given id.
    func jumpTo(topic topicId: String) {
        presentChatReplacingCurrentVC(with: topicId)
    }
}

// MARK: - Search functionality

extension FindViewController: UISearchResultsUpdating, UISearchControllerDelegate, UISearchBarDelegate {

    public func cancelPendingSearchRequest(deactivateSearch dismiss: Bool) {
        pendingSearchRequest?.cancel()
        pendingSearchRequest = nil
        if dismiss {
            searchController.isActive = false
        }
    }

    private func doSearch(queryString: String?) {
        self.interactor?.loadAndPresentContacts(searchQuery: queryString)
    }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        cancelPendingSearchRequest(deactivateSearch: false)
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
        cancelPendingSearchRequest(deactivateSearch: false)

        if transitioningOut {
            return
        }
        let queryString = getQueryString()
        let currentSearchRequest = DispatchWorkItem {
            self.doSearch(queryString: queryString)
        }
        pendingSearchRequest = currentSearchRequest
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: currentSearchRequest)
    }

    // Search controller is dismissed if user clears the query OR if the user clicked on an item
    // and is moving to another view. In the second case no need to loadAndPresentContacts because
    // fnd.leave() will be called anyway. Otherwise an update to content prevents notmal navigation.
    func didDismissSearchController(_ searchController: UISearchController) {
        cancelPendingSearchRequest(deactivateSearch: false)
        if !transitioningOut {
            self.interactor?.loadAndPresentContacts(searchQuery: nil)
        }
    }
}

extension FindViewController: ContactViewCellDelegate {
    func selected(from cell: UITableViewCell) {
        guard let indexPath = tableView.indexPathForSelectedRow else { return }
        guard let id = getUniqueId(for: indexPath) else { return }
        if indexPath.section == FindViewController.kRemoteContactsSection {
            // Save topic and user.
            guard interactor?.saveRemoteTopic(from: remoteContacts[indexPath.row]) ?? false else {
                UiUtils.showToast(message: NSLocalizedString("Failed to save group and contact info.", comment: "Error message"))
                return
            }
        }

        // Make sure there are no pending search requests.
        cancelPendingSearchRequest(deactivateSearch: false)
        transitioningOut = true

        // If the search bar is active, deactivate it.
        if searchController.isActive {
            // Disable the animation as we are going straight to another view.
            // This call takes very long time to complete.
            searchController.dismiss(animated: false, completion: { self.jumpTo(topic: id) })
        } else {
            jumpTo(topic: id)
        }
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

// UISearchBar.searchTextField is only available in iOS 13+.
// Needed so we can change placeholder font size in the search bar.
extension UISearchBar {
    var textField: UITextField? {
        return self.searchTextField
    }
}
