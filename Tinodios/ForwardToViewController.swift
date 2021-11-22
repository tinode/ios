//
//  ForwardToViewController.swift
//

import TinodeSDK
import UIKit

protocol ForwardToDelegate: AnyObject {
    func forwardMessage(_ message: Drafty, from origin: String, to topicId: String)
}

class ForwardToViewController: FindViewController {
    var delegate: ForwardToDelegate?
    var forwardedContent: Drafty!
    var forwardedFrom: String!

    private func dismiss() {
        self.navigationController?.popViewController(animated: true)
        self.dismiss(animated: true, completion: nil)
    }

    @IBAction func cancelClicked(_ sender: Any) {
        self.dismiss()
    }

    override func jumpTo(topic topicId: String) {
        self.dismiss()
        self.delegate?.forwardMessage(forwardedContent, from: forwardedFrom, to: topicId)
    }
}
