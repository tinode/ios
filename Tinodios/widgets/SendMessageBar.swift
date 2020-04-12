//
//  SendMessageBar.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

protocol SendMessageBarDelegate: class {
    func sendMessageBar(sendText: String)

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
    @IBOutlet weak var inputField: PlaceholderTextView!
    @IBOutlet weak var inputFieldHeight: NSLayoutConstraint!

    // Overlay for writing disabled. Hidden by default.
    @IBOutlet weak var allDisabledView: UIView!
    // Message "Peer's messaging is disabled. Enable". Not installed by default.
    @IBOutlet weak var peerMessagingDisabledView: UIStackView!
    @IBOutlet weak var peerMessagingDisabledHeight: NSLayoutConstraint!

    // MARK: Properties
    weak var foregroundView: UIView?

    // MARK: IBActions

    @IBAction func attach(_ sender: UIButton) {
        inputField.resignFirstResponder()

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
        delegate?.sendMessageBar(sendText: msg)
        inputField.text = nil
        textViewDidChange(inputField)
    }

    @IBAction func enablePeerMessagingClicked(_ sender: Any) {
        self.delegate?.sendMessageBar(enablePeersMessaging: true)
    }

    // MARK: - Constants

    private enum Constants {
        static let maxLines: CGFloat = 4
        static let inputFieldInsetLeading: CGFloat = 4
        static let inputFieldInsetTrailing: CGFloat = 40
        static let peerMessagingDisabledHeight: CGFloat = 30
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
        toggleNotAvailableOverlay(visible: false)
        togglePeerMessagingDisabled(visible: false)
    }

    /// MARK: - Subviews handling

    public func toggleNotAvailableOverlay(visible: Bool) {
        allDisabledView.isHidden = !visible
        isUserInteractionEnabled = !visible
    }

    public func togglePeerMessagingDisabled(visible: Bool) {
        peerMessagingDisabledView.isHidden = !visible
        peerMessagingDisabledView.isUserInteractionEnabled = visible
        peerMessagingDisabledHeight.constant = visible ? Constants.peerMessagingDisabledHeight : 0
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
