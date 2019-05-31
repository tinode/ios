//
//  PermissionsEditView.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

protocol PermissionsEditViewDelegate: class {
    func didChangePermissions(joinState: Bool,
                              readState: Bool,
                              writeState: Bool,
                              notificationsState: Bool,
                              approveState: Bool,
                              inviteState: Bool,
                              deleteState: Bool)
}

class PermissionsEditViewController: UIViewController {

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

    private var delegate: PermissionsEditViewDelegate?

    init(joinState: Bool,
         readState: Bool,
         writeState: Bool,
         notificationsState: Bool,
         approveState: Bool,
         inviteState: Bool,
         deleteState: Bool,
         delegate: PermissionsEditViewDelegate?) {
        self.joinState = joinState
        self.readState = readState
        self.writeState = writeState
        self.notificationsState = notificationsState
        self.approveState = approveState
        self.inviteState = inviteState
        self.deleteState = deleteState
        super.init(nibName: nil, bundle: nil)
        self.modalTransitionStyle = .crossDissolve
        self.modalPresentationStyle = .overCurrentContext
        self.delegate = delegate
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
            self.delegate?.didChangePermissions(
                joinState: self.joinSwitch.isOn,
                readState: self.readSwitch.isOn,
                writeState: self.writeSwitch.isOn,
                notificationsState: self.notificationsSwitch.isOn,
                approveState: self.approveSwitch.isOn,
                inviteState: self.inviteSwitch.isOn,
                deleteState: self.deleteSwitch.isOn)
        }
        self.dismiss(animated: false, completion: nil)
    }
}
