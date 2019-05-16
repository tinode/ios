//
//  FindViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

protocol FindDisplayLogic: class {
    func displayContacts(contacts: [ContactHolder])
}

class FindViewController: UITableViewController, FindDisplayLogic {
    var interactor: FindBusinessLogic?
    var contacts: [ContactHolder] = []
    var router: FindRoutingLogic?
    var searchController: UISearchController!
    var pendingSearchRequest: DispatchWorkItem? = nil

    private func setup() {
        let viewController = self
        let interactor = FindInteractor()
        let presenter = FindPresenter()
        let router = FindRouter()
        
        viewController.interactor = interactor
        viewController.router = router
        interactor.presenter = presenter
        interactor.router = router
        presenter.viewController = viewController
        router.viewController = viewController

        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.placeholder = "Search by tags"

        // Make it a-la Telegram UI instead of placing the search bar
        // in the navigation item.
        self.tableView.tableHeaderView = searchController.searchBar

        searchController.delegate = self
        // The default is true.
        searchController.dimsBackgroundDuringPresentation = false
        // Monitor when the search button is tapped.
        searchController.searchBar.delegate = self
        self.definesPresentationContext = true
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
        self.interactor?.setup()
        self.interactor?.attachToFndTopic()
        self.interactor?.loadAndPresentContacts(searchQuery: nil)
    }
    override func viewDidDisappear(_ animated: Bool) {
        self.interactor?.cleanup()
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.contacts.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FindTableViewCell", for: indexPath)

        // Configure the cell...
        let contact = contacts[indexPath.row]
        cell.textLabel?.text = contact.displayName
        cell.detailTextLabel?.text = contact.uniqueId

        return cell
    }
}

extension FindViewController {
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "Find2Messages" {
            // If the search bar is active, deactivate it.
            if searchController.isActive {
                DispatchQueue.main.async {
                    self.searchController.isActive = false
                }
            }
            router?.routeToChat(segue: segue)
        }
    }
}

// MARK: - Search functionality

extension FindViewController: UISearchResultsUpdating, UISearchControllerDelegate, UISearchBarDelegate {

    private func doSearch(queryString: String?) {
        print("Searching contacts for: \(queryString)")
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
