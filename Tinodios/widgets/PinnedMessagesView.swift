//
//  PinnedMessagesView.swift
//  Tinodios
//
//  Copyright © 2023 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK

class PinnedMessagesView: UIView {
    private static let kCornerRadius:CGFloat = 20

    @IBOutlet weak var dotSelectorView: DotSelectorImageView!
    @IBOutlet weak var pagerView: PagerView!

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
    }

    public var topicName: String?

    public var pins: [Int] = [] {
        didSet {
            dotSelectorView.dotCount = pins.count
            var pages: [UIView] = []
            if !pins.isEmpty {
                guard let topicName = topicName, let topic = Cache.tinode.getTopic(topicName: topicName) else { return }
                pins.forEach { seq in
                    guard let msg = topic.getMessage(byEffectiveSeq: seq) else { return }
                    if let promise = self.preparePreview(msg) {
                        let tv = UITextView()
                        tv.isUserInteractionEnabled = false
                        tv.backgroundColor = .systemBackground
                        pages.append(tv)
                        promise.thenApply { [weak self] content in
                            guard let pmv = self else { return nil }
                            let text = SendReplyFormatter(defaultAttributes: [:]).toAttributed(content!, fitIn: CGSize(width: pmv.pagerView.bounds.width, height: pmv.pagerView.bounds.height))
                            tv.attributedText = text
                            // Center text vertically.
                            let deadSpace = pmv.pagerView.bounds.height - tv.contentSize.height
                            let inset = max(0, deadSpace/2)
                            tv.contentInset = UIEdgeInsets(top: inset, left: tv.contentInset.left, bottom: tv.contentInset.bottom, right: tv.contentInset.right)
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
    func preparePreview(_ msg: Message) -> PromisedReply<Drafty>? {
        guard let content = msg.content else { return nil }
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
    }
}
