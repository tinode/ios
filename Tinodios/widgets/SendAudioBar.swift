//
//  SendAudioBar.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import UIKit

protocol SendAudioBarDelegate: AnyObject {
    // Send the message.
    func sendAudioBar(record: URL)
    // Dismisses reply preview.
    func dismissPreview()
}

class SendAudioBar: UIView {
    // MARK: Action delegate
    weak var delegate: SendAudioBarDelegate?
    weak var replyPreviewDelegate: PendingMessagePreviewDelegate?

    // MARK: IBOutlets
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var previewView: RichTextView!
    @IBOutlet weak var previewViewHeight: NSLayoutConstraint!
    @IBOutlet weak var deleteButton: UIButton!
    @IBOutlet weak var durationLabel: UILabel!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var waveBackground: UIView!

    // MARK: IBActions
    @IBAction func send(_ sender: UIButton) {
        delegate?.sendAudioBar(record: URL(fileURLWithPath: ""))
    }

    @IBAction func play(_ sender: Any) {
    }

    @IBAction func record(_ sender: Any) {
    }

    @IBAction func deleteRecord(_ sender: Any) {
    }

    @IBAction func cancelPreviewClicked(_ sender: Any) {
        self.togglePreviewBar(with: nil)
        self.delegate?.dismissPreview()
    }

    // MARK: - Constants
    private enum Constants {
        static let maxLines: CGFloat = 4
        static let inputFieldInsetLeading: CGFloat = 4
        static let inputFieldInsetTrailing: CGFloat = 40
    }

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

    // MARK: Properties
    weak var foregroundView: UIView?

    // MARK: - Configuration

    private func loadNib() {
        let nib = UINib(nibName: "SendAudioBar", bundle: Bundle(for: type(of: self)))
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
        waveBackground.layer.borderWidth = 0
        waveBackground.layer.cornerRadius = 18

        sendButton.isEnabled = true
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
