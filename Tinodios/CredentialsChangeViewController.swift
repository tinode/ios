//
//  CredentialsChangeViewController.swift
//  Tinodios
//
//  Copyright © 2023 Tinode. All rights reserved.
//

import PhoneNumberKit
import TinodeSDK
import UIKit

class CredentialsChangeViewController: UITableViewController {
    // UI element positions of UI in the table layout.
    private static let kSectionCurrentCredentials = 0
    private static let kSectionNewCredentials = 1
    private static let kSectionConfirmation = 2
    private static let kCurrentEmail = 0
    private static let kCurrentTel = 1
    private static let kNewEmail = 0
    private static let kNewTel = 1
    private static let kInfoLabel = 2
    private static let kRequestButton = 3

    @IBOutlet weak var currentEmailField: UITextField!
    @IBOutlet weak var currentTelField: PhoneNumberTextField!
    @IBOutlet weak var newEmailField: UITextField!
    @IBOutlet weak var newTelField: PhoneNumberTextField!
    @IBOutlet weak var infoLabel: UILabel!
    @IBOutlet weak var confirmationCodeField: UITextField!

    var currentCredential: Credential?
    private var confirmationSectionVisible = false

    private func configureTelInputField(_ field: PhoneNumberTextField) {
        field.withFlag = true
        field.withPrefix = true
        field.withExamplePlaceholder = true
        field.withDefaultPickerUI = true
    }

    private func loadData() {
        self.title = "Change Credentials"
        if let cred = currentCredential {
            switch cred.meth {
            case Credential.kMethEmail:
                currentEmailField.text = cred.val
                infoLabel.text = "We will send a message with confirmation code to the address above."
            case Credential.kMethPhone:
                currentTelField.text = cred.val
                infoLabel.text = "We will send an SMS with confirmation code to the number above."
            default:
                break
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureTelInputField(currentTelField)
        configureTelInputField(newTelField)

        UiUtils.dismissKeyboardForTaps(onView: self.view)
        loadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        self.setInterfaceColors()
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == CredentialsChangeViewController.kSectionConfirmation && !self.confirmationSectionVisible {
            return CGFloat.leastNonzeroMagnitude
        }
        return super.tableView(tableView, heightForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == CredentialsChangeViewController.kSectionConfirmation && !self.confirmationSectionVisible {
            return nil
        }
        return super.tableView(tableView, titleForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let method = self.currentCredential?.meth
        switch indexPath.section {
        case CredentialsChangeViewController.kSectionCurrentCredentials:
            if method == nil ||
                (indexPath.row == CredentialsChangeViewController.kCurrentEmail && method != Credential.kMethEmail) ||
                (indexPath.row == CredentialsChangeViewController.kCurrentTel && method != Credential.kMethPhone) {
                return CGFloat.leastNonzeroMagnitude
            }
        case CredentialsChangeViewController.kSectionNewCredentials:
            if method == nil ||
                (indexPath.row == CredentialsChangeViewController.kNewEmail && method != Credential.kMethEmail) ||
                (indexPath.row == CredentialsChangeViewController.kNewTel && method != Credential.kMethPhone) ||
                (indexPath.row == CredentialsChangeViewController.kInfoLabel && self.confirmationSectionVisible) ||
                (indexPath.row == CredentialsChangeViewController.kRequestButton && self.confirmationSectionVisible) {
                return CGFloat.leastNonzeroMagnitude
            }
        case CredentialsChangeViewController.kSectionConfirmation:
            if !self.confirmationSectionVisible {
                return CGFloat.leastNonzeroMagnitude
            }
        default:
            break
        }
        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        self.setInterfaceColors()
    }

    private func setInterfaceColors() {
        if traitCollection.userInterfaceStyle == .dark {
            self.view.backgroundColor = .black
        } else {
            self.view.backgroundColor = .white
        }
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        UiUtils.clearTextFieldError(textField)
    }

    private func validateCredential(forMethod method: String) -> String? {
        switch method {
        case Credential.kMethEmail:
            let credential = UiUtils.ensureDataInTextField(newEmailField)
            guard !credential.isEmpty, case let .email(cred) = ValidatedCredential.parse(from: credential) else {
                UiUtils.markTextFieldAsError(newEmailField)
                return nil
            }
            return cred
        case Credential.kMethPhone:
            guard newTelField.isValidNumber else {
                UiUtils.markTextFieldAsError(newTelField)
                return nil
            }
            return newTelField.phoneNumberKit.format(newTelField.phoneNumber!, toType: .e164)
        default:
            Cache.log.error("Unknown cred method: %@", method)
            return nil
        }
    }

    @IBAction func requestClicked(_ sender: Any) {
        guard let method = self.currentCredential?.meth, let value = validateCredential(forMethod: method) else {
            return
        }
        self.confirmationSectionVisible = true
        self.tableView.reloadData()
    }

    @IBAction func confirmClicked(_ sender: Any) {
    }
}
