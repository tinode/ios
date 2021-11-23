//
//  ForwardToViewController.swift
//

import TinodeSDK
import UIKit

protocol ForwardToDelegate: AnyObject {
    func forwardMessage(_ message: Drafty, preview: Drafty, from origin: String, to topicId: String)
}

class ForwardToViewController: FindViewController {
    var delegate: ForwardToDelegate?
    var forwardedContent: Drafty!
    var forwardedFrom: String!
    var forwardedPreview: Drafty!

    private func dismiss() {
        self.navigationController?.popViewController(animated: true)
        self.dismiss(animated: true, completion: nil)
    }

    @IBAction func cancelClicked(_ sender: Any) {
        self.dismiss()
    }

    override func jumpTo(topic topicId: String) {
        self.dismiss()
        self.delegate?.forwardMessage(forwardedContent, preview: forwardedPreview, from: forwardedFrom, to: topicId)
    }
}
