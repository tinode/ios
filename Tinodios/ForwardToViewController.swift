//
//  ForwardToViewController.swift
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import TinodeSDK
import UIKit

protocol ForwardToDelegate: AnyObject {
    func forwardMessage(_ message: Drafty, preview: Drafty, from origin: String, to topicId: String)
}

class ForwardToInteractor: FindInteractor {
    private let filterTopic: String
    init(filterTopic topicName: String) {
        filterTopic = topicName
    }
    override func fetchLocalContacts() -> [ContactHolder] {
        guard let topics = Utils.fetchTopics(archived: false) else { return [] }
        let finalTopics = topics.filter { $0.name != filterTopic }
        return finalTopics.map { (topic) -> ContactHolder in
            return ContactHolder(pub: topic.pub, uniqueId: topic.name)
        }
    }
}

class ForwardToViewController: FindViewController {
    var delegate: ForwardToDelegate?
    var forwardedContent: Drafty!
    var forwardedFrom: String!
    var forwardedPreview: Drafty!

    // Use ForwardToInterator for the business logic.
    override func createDependencies() -> (FindBusinessLogic, FindPresentationLogic) {
        var sourceTopic = forwardedFrom!
        if let pos = sourceTopic.range(of: ":") {
            sourceTopic.removeSubrange(pos.lowerBound..<forwardedFrom.endIndex)
        }
        return (ForwardToInteractor(filterTopic: sourceTopic), FindPresenter())
    }

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
