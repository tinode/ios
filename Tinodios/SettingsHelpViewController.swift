//
//  SettingsHelpViewController.swift
//  Tinodios
//
//  Copyright © 2020 Tinode. All rights reserved.
//

import MessageUI
import UIKit

class SettingsHelpViewController: UITableViewController {
    @IBOutlet weak var contactUs: UITableViewCell!
    @IBOutlet weak var termsOfUse: UITableViewCell!
    @IBOutlet weak var privacyPolicy: UITableViewCell!
    @IBOutlet weak var appVersion: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    private func setup() {
        UiUtils.setupTapRecognizer(
            forView: privacyPolicy,
            action: #selector(SettingsHelpViewController.privacyPolicyClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: contactUs,
            action: #selector(SettingsHelpViewController.contactUsClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: termsOfUse,
            action: #selector(SettingsHelpViewController.termsOfUseClicked),
            actionTarget: self)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let versionCode = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        self.appVersion.text = "\(version) (\(versionCode))"
    }

    @objc func termsOfUseClicked(sender: UITapGestureRecognizer) {
        UIApplication.shared.open(URL(string: "https://tinode.co/terms.html")!)
    }

    @objc func privacyPolicyClicked(sender: UITapGestureRecognizer) {
        UIApplication.shared.open(URL(string: "https://tinode.co/privacy.html")!)
    }

    @objc func contactUsClicked(sender: UITapGestureRecognizer) {
        if MFMailComposeViewController.canSendMail() {
            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = self
            mail.setToRecipients(["mailto:info@tinode.co"])
            present(mail, animated: true)
        } else {
            UiUtils.showToast(message: NSLocalizedString("Cannot send email: functionality not accessible.", comment: "Error message"))
        }
    }
}

extension SettingsHelpViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
        if let err = error {
            UiUtils.showToast(message: String(format: NSLocalizedString("Failed to send email: %@", comment: "Error message"), err.localizedDescription))
        }
    }
}
