//
//  SendMessageBar.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

class SendMessageBar: UIView {

    // MARK: IBoutlets

    @IBOutlet weak var attachButton: UIButton!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var inputField: UITextView!
    @IBOutlet weak var backgroundDecoration: UIView!
    @IBOutlet weak var inputFieldHeight: NSLayoutConstraint!

    // MARK: IBactions

    @IBAction func attach(_ sender: UIButton) {
    }

    @IBAction func send(_ sender: UIButton) {
    }

    // MARK: - Constants

    private enum Constants {
        static let maxLines: CGFloat = 4
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
        inputField.layer.borderWidth = 1.0
        inputField.layer.borderColor = UIColor.lightGray.cgColor
        inputField.layer.cornerRadius = 16.0
        inputField.autoresizingMask = [.flexibleHeight]
        inputField.delegate = self
        inputField.textContainerInset = UIEdgeInsets(
            top: inputField.textContainerInset.top,
            left: 4,
            bottom: inputField.textContainerInset.bottom,
            right: 4)

        if let font = inputField.font {
            inputFieldMaxHeight = font.lineHeight * Constants.maxLines
        }

        sendButton.isEnabled = false
        print("configured SendMessageBar \(frame)")
    }
}

extension SendMessageBar: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        //if let tv = textView as? TextViewWithPlaceholder {
        //    tv.placeholderLabel.isHidden = !textView.text.isEmpty
        //}

        let size = CGSize(width: frame.width, height: .greatestFiniteMagnitude)
        let fittingSize = inputField.sizeThatFits(size)

        if !(fittingSize.height > inputFieldMaxHeight) {
            inputField.isScrollEnabled = false
            inputFieldHeight.constant = fittingSize.height
        } else {
            textView.isScrollEnabled = true
        }

        sendButton.isEnabled = !textView.text.isEmpty
    }
}

