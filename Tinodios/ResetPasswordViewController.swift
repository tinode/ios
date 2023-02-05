//
//  ResetPasswordViewController.swift
//  Tinodios
//
//  Copyright © 2019-2023 Tinode. All rights reserved.
//

import PhoneNumberKit
import TinodeSDK
import UIKit

class ResetPasswordViewController: UITableViewController {
    // UI element positions of UI in the table layout.
    private static let kSectionCredentials = 0
    private static let kSectionNewPassword = 1
    private static let kMethodEmail = 1
    private static let kMethodTel = 2
    private static let kRequestCodeButton = 3
    private static let kIHaveCodeButton = 4

    @IBOutlet weak var promptLabel: UILabel!
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var telTextField: PhoneNumberTextField!
    @IBOutlet weak var confirmationCodeTextField: UITextField!
    @IBOutlet weak var newPasswordTextField: UITextField!

    private var passwordVisible = false
    private var passwordChangeSectionVisible = false
    private var codeRequested = false
    private var haveCode = false
    // Required credential methods.
    private var credMethods: [String]?

    override func viewDidLoad() {
        super.viewDidLoad()

        _ = try? Cache.tinode.connectDefault(inBackground: false)?.then(
            onSuccess: { _ in
                if let creds = Cache.tinode.getRequiredCredMethods(forAuthLevel: "auth") {
                    self.credMethods = creds
                }
                if self.credMethods?.isEmpty ?? true {
                    self.credMethods = [Credential.kMethEmail]
                }
                self.configurePageHeader()
                return nil
            },
            onFailure: { err in
                Cache.log.error("Error connecting to tinode %@", err.localizedDescription)
                DispatchQueue.main.async { UiUtils.showToast(message: NSLocalizedString("Service unavailable at this time. Please try again later.", comment: "Service unavailable")) }
                return nil
            }).thenFinally {
                DispatchQueue.main.async { self.tableView.reloadData() }
            }

        // Listen to text change events to clear the possible error from earlier attempt.
        emailTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        telTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        confirmationCodeTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)

        telTextField.withFlag = true
        telTextField.withPrefix = true
        telTextField.withExamplePlaceholder = true
        telTextField.withDefaultPickerUI = true

        newPasswordTextField.showSecureEntrySwitch()

        UiUtils.dismissKeyboardForTaps(onView: self.view)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if self.isMovingFromParent {
            // If the user's logged in and is voluntarily leaving the ResetPassword VC
            // by hitting the Back button.
            let tinode = Cache.tinode
            if tinode.isConnectionAuthenticated || tinode.myUid != nil {
                tinode.logout()
            }
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == ResetPasswordViewController.kSectionNewPassword && !self.passwordChangeSectionVisible {
            return CGFloat.leastNonzeroMagnitude
        }
        return super.tableView(tableView, heightForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == ResetPasswordViewController.kSectionNewPassword && !self.passwordChangeSectionVisible {
            return nil
        }
        return super.tableView(tableView, titleForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // Show only required credential fields.
        switch indexPath.section {
        case ResetPasswordViewController.kSectionCredentials:
            let method = self.credMethods?.first
            if method == nil ||
                (indexPath.row == ResetPasswordViewController.kMethodEmail && method! != Credential.kMethEmail) ||
                (indexPath.row == ResetPasswordViewController.kMethodTel && method! != Credential.kMethPhone) ||
                (indexPath.row == ResetPasswordViewController.kRequestCodeButton && (self.codeRequested || self.haveCode)) ||
                (indexPath.row == ResetPasswordViewController.kIHaveCodeButton && self.passwordChangeSectionVisible) {
                return CGFloat.leastNonzeroMagnitude
            }
        case ResetPasswordViewController.kSectionNewPassword:
            if !self.passwordChangeSectionVisible {
                return CGFloat.leastNonzeroMagnitude
            }
        default:
            break
        }
        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    private func configurePageHeader() {
        DispatchQueue.main.async {
            if self.haveCode {
                self.promptLabel.text = NSLocalizedString("Current credential", comment: "Label for email or phone number entering")
                return
            }
            switch self.credMethods!.first {
            case Credential.kMethEmail:
                self.promptLabel.text = NSLocalizedString("We will send an email with confirmation code to the address below", comment: "Email password reset prompt")
            case Credential.kMethPhone:
                self.promptLabel.text = NSLocalizedString("We will send a SMS with confirmation code to the number below", comment: "Telephone password reset prompt")
            default:
                break
            }
        }
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        textField.clearErrorSign()
    }

    @IBAction func haveCodeClicked(_ sender: Any) {
        if !self.passwordChangeSectionVisible {
            self.haveCode = true
            self.passwordChangeSectionVisible = true
            self.configurePageHeader()
            self.tableView.reloadData()
        }
    }

    private func validateCredential(forMethod method: String) -> String? {
        switch method {
        case Credential.kMethEmail:
            let credential = UiUtils.ensureDataInTextField(emailTextField)
            guard !credential.isEmpty, case let .email(cred) = ValidatedCredential.parse(from: credential) else {
                emailTextField.markAsError()
                return nil
            }
            return cred
        case Credential.kMethPhone:
            guard telTextField.isValidNumber else {
                telTextField.markAsError()
                return nil
            }
            return telTextField.phoneNumberKit.format(telTextField.phoneNumber!, toType: .e164)
        default:
            Cache.log.error("Unknown cred method: %@", method)
            return nil
        }
    }

    @IBAction func requestCodeClicked(_ sender: Any) {
        guard let method = self.credMethods?.first, let value = validateCredential(forMethod: method) else {
            return
        }
        self.showRequestProgressOverlay()
        Cache.tinode.requestResetPassword(method: method, newValue: value).then(onSuccess: { msg in
            self.passwordChangeSectionVisible = true
            DispatchQueue.main.async {
                self.telTextField.isEnabled = false
                UiUtils.showToast(message: NSLocalizedString("Confirmation code sent", comment: "Confirmation code sent"), level: .info)
            }
            self.codeRequested = true
            self.configurePageHeader()
            return nil
        }, onFailure : { err in
            Cache.log.error("Password reset error: %@", err.localizedDescription)
            self.passwordChangeSectionVisible = false
            DispatchQueue.main.async { UiUtils.showToast(message: NSLocalizedString("Invalid or unknown address", comment: "Password reset error")) }
            return nil
        }).thenFinally {
            DispatchQueue.main.async {
                self.dismissProgressOverlay()
                self.tableView.reloadData()
            }
        }
    }

    @IBAction func confirmCodeClicked(_ sender: Any) {
        guard let method = self.credMethods?.first, let value = validateCredential(forMethod: method) else {
            return
        }
        let code = UiUtils.ensureDataInTextField(confirmationCodeTextField)
        let pwd = UiUtils.ensureDataInTextField(newPasswordTextField)

        guard let auth = try? AuthScheme.codeInstance(code: code, method: method, value: value) else {
            UiUtils.showToast(message: "Invalid params")
            return
        }

        UiUtils.toggleProgressOverlay(in: self, visible: true, title: NSLocalizedString("Updating password...", comment: "Progress overlay"))
        Cache.tinode.updateAccountBasic(usingAuthScheme: auth, username: "", password: pwd).then(onSuccess: { msg in
            if let ctrl = msg?.ctrl, 200 <= ctrl.code && ctrl.code < 300 {
                DispatchQueue.main.async {
                    UiUtils.showToast(message: "Password successfully updated", level: .info)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                    self.navigationController?.popViewController(animated: true)
                }
            } else {
                DispatchQueue.main.async { UiUtils.showToast(message: "Invalid or incorrect code") }
            }
            return nil
        }, onFailure: { err in
            DispatchQueue.main.async { UiUtils.showToast(message: "Invalid or incorrect code") }
            return nil
        }).thenFinally {
            DispatchQueue.main.async {
                UiUtils.toggleProgressOverlay(in: self, visible: false)
            }
        }
    }
}
