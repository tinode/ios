//
//  ForwardMessageBar.swift
//  Tinodios
//
//  Copyright © 2021 Tinode. All rights reserved.
//

import UIKit

class ForwardMessageBar: UIView {
    @IBOutlet weak var previewView: RichTextView!
    @IBOutlet weak var previewViewHeight: NSLayoutConstraint!

    weak var delegate: (SendMessageBarDelegate & PendingMessagePreviewDelegate)?

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        loadNib()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
    }

    private func loadNib() {
        let nib = UINib(nibName: "ForwardMessageBar", bundle: Bundle(for: type(of: self)))
        let nibView = nib.instantiate(withOwner: self, options: nil).first as! UIView
        nibView.backgroundColor = UIColor.lightGray.withAlphaComponent(0.5)
        nibView.translatesAutoresizingMaskIntoConstraints = false
        self.autoresizingMask = .flexibleHeight

        addSubview(nibView)

        NSLayoutConstraint.activate([
            nibView.topAnchor.constraint(equalTo: topAnchor),
            nibView.bottomAnchor.constraint(equalTo: bottomAnchor),
            nibView.rightAnchor.constraint(equalTo: rightAnchor),
            nibView.leftAnchor.constraint(equalTo: leftAnchor)
            ])
    }

    override var intrinsicContentSize: CGSize {
        // Calculate intrinsicContentSize that will fit the preview.
        let textSize = self.previewView.sizeThatFits(CGSize(width: self.previewView.bounds.width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: self.bounds.width, height: textSize.height)
    }

    @IBAction func cancelPreviewClicked(_ sender: Any) {
        self.togglePendingPreviewBar(with: nil)
        self.delegate?.dismissPendingMessagePreview()
    }

    @IBAction func send(_ sender: Any) {
        // The delegate keeps track of the message being forwarded.
        // Let it know the user wants the pending message to be sent.
        delegate?.sendMessageBar(sendText: "")
    }

    public func togglePendingPreviewBar(with message: NSAttributedString?) {
        if let message = message, let delegate = self.delegate {
            let textBounds = delegate.pendingPreviewMessageSize(forMessage: message)
            previewViewHeight.constant = textBounds.height
            previewView.attributedText = message
            previewView.isHidden = false
        } else {
            previewViewHeight.constant = CGFloat.zero
            previewView.attributedText = nil
            previewView.isHidden = true
        }
        layoutIfNeeded()
    }
}
