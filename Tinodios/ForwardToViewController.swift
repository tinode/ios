//
//  ForwardToViewController.swift
//

import TinodeSDK
import UIKit

protocol ForwardToDelegate: AnyObject {
    func forwardMessage(_ message: Drafty, from originTopic: String, to topicId: String)
}

class ForwardToViewController: FindViewController {
    var delegate: ForwardToDelegate?
    var forwardedContent: Drafty!
    var forwardedFromTopic: String!

    private func dismiss() {
        self.navigationController?.popViewController(animated: true)
        self.dismiss(animated: true, completion: nil)
    }

    @IBAction func cancelClicked(_ sender: Any) {
        self.dismiss()
    }

    override func jumpTo(topic topicId: String) {
        self.dismiss()
        self.delegate?.forwardMessage(forwardedContent, from: forwardedFromTopic, to: topicId)
    }
}
