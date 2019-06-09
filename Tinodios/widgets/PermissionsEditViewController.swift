//
//  PermissionsEditView.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

class PermissionsEditViewController: UIViewController {
    public enum PermissionType {
        case join, read, write, notifications, approve, invite, delete
    }
    public typealias PermissionsTuple = (
        join: Bool, read: Bool, write: Bool, notifications: Bool,
        approve: Bool, invite: Bool, delete: Bool)
    public typealias OnChangeHandler = ((
        _ permissions: PermissionsTuple) -> ())

    @IBOutlet weak var alertView: UIView!
    @IBOutlet weak var joinSwitch: UISwitch!
    @IBOutlet weak var readSwitch: UISwitch!
    @IBOutlet weak var writeSwitch: UISwitch!
    @IBOutlet weak var notificationsSwitch: UISwitch!
    @IBOutlet weak var approveSwitch: UISwitch!
    @IBOutlet weak var inviteSwitch: UISwitch!
    @IBOutlet weak var deleteSwitch: UISwitch!

    private var joinState: Bool
    private var readState: Bool
    private var writeState: Bool
    private var notificationsState: Bool
    private var approveState: Bool
    private var inviteState: Bool
    private var deleteState: Bool
    private var disabledPermissions: [PermissionType]?

    private var onChange: OnChangeHandler?

    init(permissionsTuple: PermissionsTuple,
         disabledPermissions: [PermissionType]?,
         onChangeHandler: PermissionsEditViewController.OnChangeHandler?) {
        self.joinState = permissionsTuple.join
        self.readState = permissionsTuple.read
        self.writeState = permissionsTuple.write
        self.notificationsState = permissionsTuple.notifications
        self.approveState = permissionsTuple.approve
        self.inviteState = permissionsTuple.invite
        self.deleteState = permissionsTuple.delete
        super.init(nibName: nil, bundle: nil)
        self.modalTransitionStyle = .crossDissolve
        self.modalPresentationStyle = .overCurrentContext
        self.onChange = onChangeHandler
        self.disabledPermissions = disabledPermissions
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override func viewDidLoad() {
        super.viewDidLoad()

        let cornerRadius: CGFloat = 4
        alertView.layer.cornerRadius = cornerRadius

        let backgroundColor: UIColor = .black
        let backgroundOpacity: CGFloat = 0.5
        view.backgroundColor = backgroundColor.withAlphaComponent(backgroundOpacity)
        self.joinSwitch.isOn = joinState
        self.readSwitch.isOn = readState
        self.writeSwitch.isOn = writeState
        self.notificationsSwitch.isOn = notificationsState
        self.approveSwitch.isOn = approveState
        self.inviteSwitch.isOn = inviteState
        self.deleteSwitch.isOn = deleteState
        if let disablePermissions = self.disabledPermissions {
            for p in disablePermissions {
                switch p {
                case .join: self.joinSwitch.isEnabled = false
                case .read: self.readSwitch.isEnabled = false
                case .write: self.writeSwitch.isEnabled = false
                case .notifications: self.notificationsSwitch.isEnabled = false
                case .approve: self.approveSwitch.isEnabled = false
                case .invite: self.inviteSwitch.isEnabled = false
                case .delete: self.deleteSwitch.isEnabled = false
                }
            }
        }
    }
    func show(over viewController: UIViewController?) {
        guard let viewController = viewController else { return }
        viewController.present(self, animated: false, completion: nil)
    }
    @IBAction func cancelClicked(_ sender: Any) {
        self.dismiss(animated: false, completion: nil)
    }
    @IBAction func okayClicked(_ sender: Any) {
        if self.joinSwitch.isOn != self.joinState ||
           self.readSwitch.isOn != self.readState ||
           self.writeSwitch.isOn != self.writeState ||
           self.notificationsSwitch.isOn != self.notificationsState ||
           self.approveSwitch.isOn != self.approveState ||
           self.inviteSwitch.isOn != self.inviteState ||
           self.deleteSwitch.isOn != self.deleteState {
            self.onChange?((self.joinSwitch.isOn,
                            self.readSwitch.isOn,
                            self.writeSwitch.isOn,
                            self.notificationsSwitch.isOn,
                            self.approveSwitch.isOn,
                            self.inviteSwitch.isOn,
                            self.deleteSwitch.isOn))
        }
        self.dismiss(animated: false, completion: nil)
    }
}
