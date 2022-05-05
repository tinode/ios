//
//  SendMessageBar.swift
//  Tinodios
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import UIKit

enum AudioRecordingAction {
    case start
    case stopAndSend
    case lock
    case cancel
    case pauseRecording
    case playback
    case pausePlayback
}

protocol SendMessageBarDelegate: AnyObject {
    func sendMessageBar(sendText: String)
    func sendMessageBar(attachment: Bool)
    func sendMessageBar(textChangedTo text: String)
    func sendMessageBar(enablePeersMessaging: Bool)
    func sendMessageBar(recordAudio: AudioRecordingAction)
}

class SendMessageBar: UIView {
    private static let kSendButtonPointsNormal: CGFloat = 26
    private static let kSendButtonPointsPressed: CGFloat = 40
    private static let kSendButtonSizeNormal: CGFloat = 32
    private static let kSendButtonSizePressed: CGFloat = 48
    private static let kSendButtonImageWave = UIImage(systemName: "waveform.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: SendMessageBar.kSendButtonPointsNormal))!
    private static let kSendButtonImageWavePressed = UIImage(systemName: "waveform.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: SendMessageBar.kSendButtonPointsPressed))!
    private static let kSendButtonImageArrow = UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: SendMessageBar.kSendButtonPointsNormal))!

    // MARK: Action delegate

    weak var delegate: (SendMessageBarDelegate & PendingMessagePreviewDelegate)?

    // MARK: IBOutlets

    @IBOutlet weak var attachButton: UIButton!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var sendButtonSize: NSLayoutConstraint!
    @IBOutlet weak var sendButtonHorizontal: NSLayoutConstraint!
    @IBOutlet weak var sendButtonVertical: NSLayoutConstraint!

    // 
    @IBOutlet weak var verticalSliderView: UIView!
    @IBOutlet weak var horizontalSliderView: UIView!

    // Constraints.
    private var sendButtonConstrains: CGPoint!
    // Position in SendMessageBar coordinates.
    private var sendButtonLocation: CGPoint!

    @IBOutlet weak var inputField: PlaceholderTextView!
    @IBOutlet weak var inputFieldHeight: NSLayoutConstraint!

    // Overlay for writing disabled. Hidden by default.
    @IBOutlet weak var allDisabledView: UIView!
    // Message "Peer's messaging is disabled. Enable". Not installed by default.
    @IBOutlet weak var peerMessagingDisabledView: UIStackView!
    @IBOutlet weak var peerMessagingDisabledHeight: NSLayoutConstraint!
    @IBOutlet weak var previewView: RichTextView!
    @IBOutlet weak var previewViewHeight: NSLayoutConstraint!

    // MARK: Properties
    weak var foregroundView: UIView?

    public var pendingPreviewText: NSAttributedString? {
        get { return previewView.attributedText.length != .zero ? previewView.attributedText : nil }
        set { previewView.attributedText = newValue }
    }

    var previewMaxWidth: CGFloat {
        return inputField.frame.width - Constants.kPreviewCancelButtonMaxWidth
    }

    // MARK: IBActions

    @IBAction func attach(_ sender: UIButton) {
        inputField.resignFirstResponder()

        let alert = UIAlertController(title: "Attachment", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Image", style: .default, handler: { _ in
            self.delegate?.sendMessageBar(attachment: false)
        }))
        alert.addAction(UIAlertAction(title: "File", style: .default, handler: { _ in
            self.delegate?.sendMessageBar(attachment: true)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        self.window?.rootViewController?.present(alert, animated: true, completion: nil)
    }

    @IBAction func send(_ sender: UIButton) {
        let msg = inputField.actualText.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty {
            return
        }
        delegate?.sendMessageBar(sendText: msg)
        inputField.text = nil
        textViewDidChange(inputField)
    }

    private func endRecording() {
        UIView.animate(withDuration: 0.15, delay: 0, options: UIView.AnimationOptions.curveEaseIn, animations: {
            self.sendButton.imageView?.image = SendMessageBar.kSendButtonImageWave
            self.sendButtonSize.constant = SendMessageBar.kSendButtonSizeNormal
            self.sendButtonHorizontal.constant = self.sendButtonConstrains.x
            self.sendButtonVertical.constant = self.sendButtonConstrains.y
            self.verticalSliderView.isHidden = true
            self.horizontalSliderView.isHidden = true
            self.layoutIfNeeded()
        }, completion: nil)
    }

    // Handle audio recorder button swipes and presses.
    @IBAction func longPressed(sender: UILongPressGestureRecognizer) {
        if !inputField.actualText.isEmpty {
            return
        }

        switch sender.state {
        case .began:
            let loc = sender.location(in: self)
            self.sendButtonConstrains = CGPoint(x: self.sendButtonHorizontal.constant, y: self.sendButtonVertical.constant)
            self.sendButtonLocation = CGPoint(x: loc.x, y: loc.y)
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.2, delay: 0, options: UIView.AnimationOptions.curveEaseIn, animations: {
                    self.sendButtonSize.constant = SendMessageBar.kSendButtonSizePressed
                    self.sendButton.imageView?.image = SendMessageBar.kSendButtonImageWavePressed
                    self.verticalSliderView.isHidden = false
                    self.horizontalSliderView.isHidden = false
                }, completion: nil)
            }
            self.delegate?.sendMessageBar(recordAudio: .start)
        case .ended:
            endRecording()
            self.delegate?.sendMessageBar(recordAudio: .stopAndSend)
        case .changed:
            // Constrain movements to either strictly horizontal or strictly vertical.
            let loc = sender.location(in: self)
            // dX and dY are negative: the movement is up and to the left.
            var dX = min(0, loc.x - sendButtonLocation.x)
            var dY = min(0, loc.y - sendButtonLocation.y)

            if abs(dX) > abs(dY) {
                // Horizontal move.
                dY = 0
            } else {
                // Vertical move.
                dX = 0
            }
            if dX < -56 {
                sender.isEnabled = false
                endRecording()
                self.delegate?.sendMessageBar(recordAudio: .cancel)
                sender.isEnabled = true
            } else {
                self.sendButtonHorizontal.constant = sendButtonConstrains.x + dX
                self.sendButtonVertical.constant = sendButtonConstrains.y + dY
            }
        default:
            print(sender.state.rawValue)
        }
    }

    @IBAction func enablePeerMessagingClicked(_ sender: Any) {
        self.delegate?.sendMessageBar(enablePeersMessaging: true)
    }

    @IBAction func cancelPreviewClicked(_ sender: Any) {
        self.togglePendingPreviewBar(with: nil)
        self.delegate?.dismissPendingMessagePreview()
    }

    // MARK: - Constants

    private enum Constants {
        static let maxLines: CGFloat = 4
        static let inputFieldInsetLeading: CGFloat = 4
        static let inputFieldInsetTrailing: CGFloat = 40
        static let peerMessagingDisabledHeight: CGFloat = 30
        static let kPreviewCancelButtonMaxWidth: CGFloat = 36
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
        horizontalSliderView.alpha = 0.8
        verticalSliderView.alpha = 0.8

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
        togglePeerMessagingDisabled(visible: false)
        togglePendingPreviewBar(with: nil)
    }

    // MARK: - Subviews handling

    public func toggleNotAvailableOverlay(visible: Bool) {
        allDisabledView.isHidden = !visible
        isUserInteractionEnabled = !visible
    }

    public func togglePeerMessagingDisabled(visible: Bool) {
        peerMessagingDisabledView.isHidden = !visible
        peerMessagingDisabledView.isUserInteractionEnabled = visible
        peerMessagingDisabledHeight.constant = visible ? Constants.peerMessagingDisabledHeight : 0
    }

    public func togglePendingPreviewBar(with message: NSAttributedString?) {
        if let message = message, let delegate = self.delegate {
            let textbounds = delegate.pendingPreviewMessageSize(forMessage: message)
            previewViewHeight.constant = textbounds.height
            pendingPreviewText = message
            previewView.isHidden = false
        } else {
            previewViewHeight.constant = CGFloat.zero
            pendingPreviewText = nil
            previewView.isHidden = true
        }
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

        if inputField.actualText.isEmpty {
            self.sendButton.imageView?.image = SendMessageBar.kSendButtonImageWave
        } else {
            self.sendButton.imageView?.image = SendMessageBar.kSendButtonImageArrow
        }
    }
}
