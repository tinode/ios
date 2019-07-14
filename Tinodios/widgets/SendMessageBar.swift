//
//  SendMessageBar.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

protocol SendMessageBarDelegate: class {
    func sendMessageBar(sendText: String) -> Bool?

    func sendMessageBar(attachment: Bool)

    func sendMessageBar(textChangedTo text: String)

    func sendMessageBar(enablePeersMessaging: Bool)
}

class SendMessageBar: UIView {

    // MARK: Action delegate

    weak var delegate: SendMessageBarDelegate?

    // MARK: IBOutlets

    @IBOutlet weak var attachButton: UIButton!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var inputField: UITextView!
    @IBOutlet weak var inputFieldHeight: NSLayoutConstraint!

    // MARK: Properties
    weak var foregroundView: UIView?

    // MARK: IBActions

    @IBAction func attach(_ sender: UIButton) {
        let alert = UIAlertController(title: "Attachment", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Image", style: .default, handler: { action in
            self.delegate?.sendMessageBar(attachment: false)
        }))
        alert.addAction(UIAlertAction(title: "File", style: .default, handler: { action in
            self.delegate?.sendMessageBar(attachment: true)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        self.window?.rootViewController?.present(alert, animated: true, completion: nil)
    }

    @IBAction func send(_ sender: UIButton) {
        let msg = inputField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty {
            return
        }
        if delegate?.sendMessageBar(sendText: msg) ?? false {
            inputField.text = nil
            textViewDidChange(inputField)
        }
    }

    // MARK: - Constants

    private enum Constants {
        static let maxLines: CGFloat = 4
        static let inputFieldInsetLeading: CGFloat = 4
        static let inputFieldInsetTrailing: CGFloat = 40
    }

    // MARK: - Private properties

    private var inputFieldMaxHeight: CGFloat = 120

    // MARK: - Initializers

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        loadNib()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
    }

    // This is needed for proper calculation of size from constraints.
    override var intrinsicContentSize: CGSize {
        return CGSize.zero
    }

    // MARK: - Configuration

    private func loadNib() {
        let nib = UINib(nibName: "SendMessageBar", bundle: Bundle(for: type(of: self)))
        let nibView = nib.instantiate(withOwner: self, options: nil).first as! UIView
        nibView.backgroundColor = UIColor.lightGray.withAlphaComponent(0.5)
        nibView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nibView)
        NSLayoutConstraint.activate([
            nibView.topAnchor.constraint(equalTo: topAnchor),
            nibView.bottomAnchor.constraint(equalTo: bottomAnchor),
            nibView.rightAnchor.constraint(equalTo: rightAnchor),
            nibView.leftAnchor.constraint(equalTo: leftAnchor)
            ])
        configure()
    }

    private func configure() {
        inputField.layer.borderWidth = 0
        inputField.layer.cornerRadius = 18
        inputField.autoresizingMask = [.flexibleHeight]
        inputField.delegate = self
        inputField.textContainerInset = UIEdgeInsets(
            top: inputField.textContainerInset.top,
            left: Constants.inputFieldInsetLeading,
            bottom: inputField.textContainerInset.bottom,
            right: Constants.inputFieldInsetTrailing)

        if let font = inputField.font {
            inputFieldMaxHeight = font.lineHeight * Constants.maxLines
        }

        sendButton.isEnabled = false
    }
}

extension SendMessageBar: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        delegate?.sendMessageBar(textChangedTo: textView.text)

        let size = CGSize(width: frame.width - Constants.inputFieldInsetLeading - Constants.inputFieldInsetTrailing, height: .greatestFiniteMagnitude)
        let fittingSize = inputField.sizeThatFits(size)

        if !(fittingSize.height > inputFieldMaxHeight) {
            inputField.isScrollEnabled = false
            inputFieldHeight.constant = fittingSize.height + 1 // Not sure why but it seems to be off by 1
        } else {
            textView.isScrollEnabled = true
        }

        sendButton.isEnabled = !textView.text.isEmpty
    }
}

extension SendMessageBar {
    private func makeOverlayView() -> UIView {
        let overlay = UIView()
        overlay.alpha = 0.8
        overlay.backgroundColor = UIColor.white
        overlay.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(overlay)
        if #available(iOS 11.0, *) {
            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: self.safeAreaLayoutGuide.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: self.safeAreaLayoutGuide.bottomAnchor),
                overlay.leadingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.trailingAnchor)])
        } else {
            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: self.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                overlay.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: self.trailingAnchor)])
        }
        return overlay
    }
    public func showNotAvailableOverlay() {
        guard self.foregroundView == nil else { return }
        // Blurring layer over the messages.
        let overlay = makeOverlayView()

        let notAvailableLabel = UILabel()
        notAvailableLabel.text = "Not available"
        notAvailableLabel.sizeToFit()
        notAvailableLabel.numberOfLines = 0
        notAvailableLabel.textAlignment = .center
        notAvailableLabel.font = UIFont.boldSystemFont(ofSize: 18)
        notAvailableLabel.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(notAvailableLabel)
        // Pin it to the superview center.
        NSLayoutConstraint.activate([
            notAvailableLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            notAvailableLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)])
        // Disable user interaction for the message view.
        self.isUserInteractionEnabled = false
        self.foregroundView = overlay
    }
    public func showPeersMessagingDisabledOverlay() {
        guard self.foregroundView == nil else { return }
        // Blurring layer over the messages.
        let overlay = makeOverlayView()

        let notAvailableLabel = UILabel()
        notAvailableLabel.text = "Peer's messaging is disabled"
        notAvailableLabel.sizeToFit()
        notAvailableLabel.numberOfLines = 0
        notAvailableLabel.textAlignment = .center
        notAvailableLabel.font = UIFont.boldSystemFont(ofSize: 16)
        notAvailableLabel.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(notAvailableLabel)
        // Pin it to the superview center.
        NSLayoutConstraint.activate([
            notAvailableLabel.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 10),
            notAvailableLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)])

        let enableButton = UIButton()//frame: CGRect(x: 0, y: 0, width: 150, height: 50))
        enableButton.setTitle("Enable", for: .normal)
        enableButton.setTitleColor(UIColor.blue, for: .normal)

        enableButton.sizeToFit()
        //enableButton.backgroundColor = UIColor.red
        enableButton.addTarget(self, action: #selector(self.enablePeersMessagingClicked), for: .touchUpInside)
        enableButton.isUserInteractionEnabled = true
        enableButton.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(enableButton)
        NSLayoutConstraint.activate([
            enableButton.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -10),
            enableButton.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)])
        self.foregroundView = overlay
    }
    @objc private func enablePeersMessagingClicked(sender: UIButton!) {
        self.delegate?.sendMessageBar(enablePeersMessaging: true)
    }
    public func removeNotAvailableOverlay() {
        guard self.foregroundView != nil else { return }
        self.foregroundView!.removeFromSuperview()
        self.foregroundView = nil
        self.isUserInteractionEnabled = true
    }
}
