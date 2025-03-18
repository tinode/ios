//
//  PinnedMessagesView.swift
//  Tinodios
//
//  Copyright © 2023-2025 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK

/// A protocol used to detect taps in the pinned messages carusel.
protocol PinnedMessagesDelegate: AnyObject {
    /// Tap on Cancel button.
    func didTapCancel(seq: Int)
    /// Tap on the message.
    func didTapMessage(seq: Int)
}

class PinnedMessagesView: UICollectionReusableView {
    private static let kCornerRadius:CGFloat = 25
    private static let kPinnedCollectionHeight = MessageViewController.Constants.kPinnedMessagesViewHeight - 4

    @IBOutlet weak var dotSelectorView: DotSelectorImageView!
    @IBOutlet weak var pagerView: PagerView!

    public var delegate: PinnedMessagesDelegate?

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        loadNib()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
    }

    private func loadNib() {
        let nib = UINib(nibName: "PinnedMessagesView", bundle: Bundle(for: type(of: self)))
        let nibView = nib.instantiate(withOwner: self, options: nil).first as! UIView
        nibView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(nibView)

        NSLayoutConstraint.activate([
            nibView.topAnchor.constraint(equalTo: topAnchor),
            nibView.bottomAnchor.constraint(equalTo: bottomAnchor),
            nibView.rightAnchor.constraint(equalTo: rightAnchor),
            nibView.leftAnchor.constraint(equalTo: leftAnchor)
            ])

        dotSelectorView.dotCount = 3
        pagerView.delegate = self
    }

    @IBAction func unpinMessageClick(_ sender: Any) {
        delegate?.didTapCancel(seq: pins[selectedPage])
    }

    public var topicName: String?

    public var pins: [Int] = [] {
        didSet {
            dotSelectorView.dotCount = pins.count
            var pages: [UIView] = []
            if !pins.isEmpty {
                guard let topicName = topicName, let topic = Cache.tinode.getTopic(topicName: topicName) else { return }
                pins.forEach { seq in
                    if let promise = self.preparePreview(topic.getMessage(byEffectiveSeq: seq)) {
                        let tv = UITextView()
                        tv.delegate = self
                        tv.backgroundColor = .systemBackground
                        tv.autocorrectionType = .no
                        tv.spellCheckingType = .no
                        pages.append(tv)
                        promise.thenApply { [weak self] content in
                            guard let pmv = self else { return nil }
                            let text = SendReplyFormatter(defaultAttributes: [:]).toAttributed(content!, fitIn: CGSize(width: pmv.pagerView.bounds.width, height: pmv.pagerView.bounds.height))
                            tv.attributedText = text
                            tv.sizeToFit()
                            // Center text vertically.
                            let topInset = max(0, (PinnedMessagesView.kPinnedCollectionHeight - tv.contentSize.height)/2)
                            tv.contentInset = UIEdgeInsets(top: topInset, left: tv.contentInset.left, bottom: tv.contentInset.bottom, right: tv.contentInset.right)
                            return nil
                        }
                    }
                }
            }
            pagerView.pages = pages
        }
    }

    private var selectedPage: Int = 0
    public var selected: Int {
        get {
            return selectedPage
        }
        set(newValue)  {
            if newValue >= 0 && newValue < pins.count && newValue != selectedPage {
                selectedPage = newValue
                dotSelectorView.selected = selectedPage
            }
        }
    }

    // Convert message into a quote ready for sending as a reply.
    func preparePreview(_ msg: Message?) -> PromisedReply<Drafty>? {
        let contentMissing = NSLocalizedString("not found", comment: "Content of a pinned message when the message is missing")
        guard let msg = msg else {
            return PromisedReply<Drafty>(value: Drafty.init(plainText: contentMissing))
        }
        guard let content = msg.content else {
            if msg.isDeleted {
                return PromisedReply<Drafty>(value: Drafty.init(plainText: NSLocalizedString("message deleted", comment: "Content of a pinned message when the message is deleted")))
            }
            return PromisedReply<Drafty>(value: Drafty.init(plainText: contentMissing))
        }

        // Strip unneeded content and shorten.
        var reply = content.replyContent(length: UiUtils.kQuotedReplyLength, maxAttachments: 1)
        let createThumbnails = ThumbnailTransformer()
        reply = reply.transform(createThumbnails)
        let whenDone = PromisedReply<Drafty>()
        createThumbnails.completionPromise.thenApply {_ in
            try? whenDone.resolve(result: reply)
            return nil
        }
        return whenDone
    }
}

extension PinnedMessagesView: PagerViewDelegate {
    func didSelectPage(index: Int) {
        dotSelectorView.selected = index
        self.selectedPage = index
    }
}

extension PinnedMessagesView: UITextViewDelegate {
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveLinear, animations: {
            textView.backgroundColor = .secondarySystemBackground
        }, completion: { _ in
            textView.backgroundColor = .systemBackground
        })

        delegate?.didTapMessage(seq: pins[selectedPage])
        return false
    }
}
