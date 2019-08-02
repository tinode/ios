//
//  PermissionsEditView.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

class PermissionsEditViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private static let kAllPermissions: [Character] = ["J","R","W","P","A","S","D","O"]
    private static let kPermissions: [Character : String] = ["J" : "Join", "R" : "Read", "W" : "Write", "P" : "Receive notifications", "A" : "Approve new members", "S" : "Invite new members", "D" : "Delete messages", "O" : "Full control (owner)"]

    public typealias ChangeHandler = ((_ permissions: String) -> ())

    private static let buttonBorderColor = UIColor(fromHexCode: 0xFFE0E0E0)

    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var tableViewHeight: NSLayoutConstraint!
    @IBOutlet weak var alertView: UIView!
    @IBOutlet weak var okButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton!

    private var onChange: ChangeHandler?
    private var visiblePermissions: [Character] = []
    private var initialState: Set<Character>?
    private var selectedPermissions: Set<Character>?

    init(set state: String, disabled: String?, changeHandler: PermissionsEditViewController.ChangeHandler?) {
        super.init(nibName: nil, bundle: nil)
        modalTransitionStyle = .crossDissolve
        modalPresentationStyle = .overCurrentContext
        onChange = changeHandler

        // Setup the tableView data source with one row = one permission.
        initialState = Set(Array(state))
        selectedPermissions = Set(Array(state))
        if let disabled = disabled {
            visiblePermissions = PermissionsEditViewController.kAllPermissions.filter({ (char) -> Bool in
                return !disabled.contains(char)
            })
        } else {
            visiblePermissions = PermissionsEditViewController.kAllPermissions
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        cancelButton.addBorder(side: .top, color: PermissionsEditViewController.buttonBorderColor, width: 1)
        cancelButton.addBorder(side: .right, color: PermissionsEditViewController.buttonBorderColor, width: 1)
        okButton.addBorder(side: .top, color: PermissionsEditViewController.buttonBorderColor, width: 1)

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.delegate = self
        tableView.dataSource = self
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Make table as tall as its content.
        tableViewHeight.constant = tableView.contentSize.height
    }

    /// MARK: - UITableView delegates

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return visiblePermissions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")!
        cell.backgroundColor = .groupTableViewBackground

        let x = visiblePermissions[indexPath.row]
        cell.textLabel?.text = PermissionsEditViewController.kPermissions[x]
        // set selected or deselected
        cell.accessoryType = selectedPermissions!.contains(x) ? .checkmark : .none
        return cell
    }

    // Tap on table Row
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)

        guard let cell = tableView.cellForRow(at: indexPath) else { return }
        let x = visiblePermissions[indexPath.row]
        if selectedPermissions!.contains(x) {
            selectedPermissions!.remove(x)
            cell.accessoryType = .none
        } else {
            selectedPermissions!.insert(x)
            cell.accessoryType = .checkmark
        }
    }

    func show(over viewController: UIViewController?) {
        guard let viewController = viewController else { return }
        viewController.present(self, animated: true, completion: nil)
    }

    /// MARK: - Button clicks

    @IBAction func cancelClicked(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }

    @IBAction func okayClicked(_ sender: Any) {
        let removed = initialState!.subtracting(selectedPermissions!)
        let added = selectedPermissions!.subtracting(initialState!)
        var change = ""
        if added.count > 0 {
            change += "+\(String(added))"
        }
        if removed.count > 0 {
            change += "-\(String(removed))"
        }
        if change.count > 0 {
            self.onChange?(change)
        }
        self.dismiss(animated: true, completion: nil)
    }
}
