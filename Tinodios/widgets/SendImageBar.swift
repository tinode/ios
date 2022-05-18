//
//  SendMessageBar.swift
//  Tinodios
//
//  Copyright © 2020-2022 Tinode LLC. All rights reserved.
//

import UIKit

protocol SendImageBarDelegate: AnyObject {
    // Send the message.
    func sendImageBar(caption: String?)
    // Dismisses reply preview.
    func dismissPreview()
}

class SendImageBar: UIView {

    // MARK: Action delegate
    weak var delegate: SendImageBarDelegate?
    weak var replyPreviewDelegate: PendingMessagePreviewDelegate?

    // MARK: IBOutlets
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var inputField: PlaceholderTextView!
    @IBOutlet weak var inputFieldHeight: NSLayoutConstraint!
    // Reply/forward previews.
    @IBOutlet weak var previewView: RichTextView!
    @IBOutlet weak var previewViewHeight: NSLayoutConstraint!

    // Overlay for 'writing disabled'. Hidden by default.
    @IBOutlet weak var allDisabledView: UIView!

    // MARK: Properties
    weak var foregroundView: UIView?

    // MARK: IBActions
    @IBAction func send(_ sender: UIButton) {
        let caption = inputField.actualText.trimmingCharacters(in: .whitespacesAndNewlines)
        delegate?.sendImageBar(caption: caption)
        inputField.text = nil
        textViewDidChange(inputField)
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
        let nib = UINib(nibName: "SendImageBar", bundle: Bundle(for: type(of: self)))
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

        sendButton.isEnabled = true
        toggleNotAvailableOverlay(visible: false)
    }

    // MARK: - Subviews handling
    public func toggleNotAvailableOverlay(visible: Bool) {
        allDisabledView.isHidden = !visible
        isUserInteractionEnabled = !visible
    }

    @IBAction func cancelPreviewClicked(_ sender: Any) {
        self.togglePreviewBar(with: nil)
        self.delegate?.dismissPreview()
    }

    public func togglePreviewBar(with message: NSAttributedString?) {
        if let message = message, let delegate = self.replyPreviewDelegate {
            let textBounds = delegate.pendingPreviewMessageSize(forMessage: message)
            previewViewHeight.constant = textBounds.height
            previewView.attributedText = message
            previewView.isHidden = false
        } else {
            previewViewHeight.constant = CGFloat.zero
            previewView.attributedText = nil
            previewView.isHidden = true
        }
    }
}

extension SendImageBar: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        let size = CGSize(width: frame.width - Constants.inputFieldInsetLeading - Constants.inputFieldInsetTrailing, height: .greatestFiniteMagnitude)
        let fittingSize = inputField.sizeThatFits(size)

        if fittingSize.height <= inputFieldMaxHeight {
            inputField.isScrollEnabled = false
            inputFieldHeight.constant = fittingSize.height + 1 // Not sure why but it seems to be off by 1
        } else {
            textView.isScrollEnabled = true
        }
    }
}
