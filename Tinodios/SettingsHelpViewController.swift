//
//  SettingsHelpViewController.swift
//  Tinodios
//
//  Copyright © 2020 Tinode. All rights reserved.
//

import MessageUI
import TinodeSDK
import TinodiosDB
import UIKit

class SettingsHelpViewController: UITableViewController {
    // 44px is the default UITableView row height.
    // TODO: may be 88px for retina display. Handle it.
    private static let kDefaultRowHeight: CGFloat = 44

    @IBOutlet weak var contactUs: UITableViewCell!
    @IBOutlet weak var termsOfUse: UITableViewCell!
    @IBOutlet weak var privacyPolicy: UITableViewCell!
    @IBOutlet weak var appVersion: UILabel!
    @IBOutlet weak var logoView: UIImageView!
    @IBOutlet weak var serviceNameLabel: UILabel!
    @IBOutlet weak var serviceLinkLabel: UILabel!
    @IBOutlet weak var serverAddressLabel: UILabel!
    @IBOutlet weak var poweredByView: UIView!

    private var tosUrl: URL!
    private var privacyUrl: URL!
    private var isUsingCustomBranding = false
    private var contentHeight: CGFloat = 0

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

        self.tosUrl = URL(string: SharedUtils.tosUrl ?? "https://tinode.co/terms.html")
        self.privacyUrl = URL(string: SharedUtils.privacyUrl ?? "https://tinode.co/privacy.html")

        // Logo.
        if let logo = SharedUtils.largeIcon {
            logoView.image = logo
        }
        // Service name.
        if let serviceName = SharedUtils.serviceName {
            serviceNameLabel.text = serviceName
        }
        // Service link (strip path from privacy url).
        var components = URLComponents()
        components.scheme = privacyUrl!.scheme
        components.host = privacyUrl!.host
        serviceLinkLabel.text = components.url!.absoluteString
        // Server address.
        let (host, tls) = Tinode.getConnectionParams()
        serverAddressLabel.text = (tls ? "https://" : "http://") + host

        // Precompute content height.
        // Table is confitured as static cells. Can use simple loop.
        self.contentHeight = 0
        for i in 0..<tableView.numberOfSections {
            let numRows = tableView.numberOfRows(inSection: i)
            for j in 0..<numRows {
                let h = tableView(self.tableView, heightForRowAt: IndexPath(row: j, section: i))
                self.contentHeight += h > 0 ? h : SettingsHelpViewController.kDefaultRowHeight
            }
        }

        if SharedUtils.appId != nil {
            self.isUsingCustomBranding = true
        }
        self.poweredByView.isHidden = !isUsingCustomBranding
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if isUsingCustomBranding {
            // Adjust "Powered by" view position.
            let topPadding = self.tableView.safeAreaInsets.top
            let bottomPadding = self.tableView.safeAreaInsets.bottom
            // Total space available below table content and the bottom.
            let height = tableView.frame.height - topPadding - bottomPadding - self.contentHeight
            // height < 0 means "Powered By" isn't visible.
            let h = height > 0 ? height : SettingsHelpViewController.kDefaultRowHeight
            if h >= SettingsHelpViewController.kDefaultRowHeight && poweredByView.frame.size.height != h {
                poweredByView.frame.size.height = h
            }
        }
    }

    @objc func termsOfUseClicked(sender: UITapGestureRecognizer) {
        UIApplication.shared.open(self.tosUrl)
    }

    @objc func privacyPolicyClicked(sender: UITapGestureRecognizer) {
        UIApplication.shared.open(self.privacyUrl)
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
