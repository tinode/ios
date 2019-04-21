//
//  ChatListAdapter.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import UIKit
import TinodeSDK

protocol ChatListBusinessLogic: class {
    func loadAndPresentTopics()
    func attachToMeTopic()
    func updateChat(_ name: String)
    func cleanup()
}

protocol ChatListDataStore: class {
    var topics: [DefaultComTopic]? { get set }
}

class ChatListInteractor: ChatListBusinessLogic, ChatListDataStore {
    private class MeListener: DefaultMeTopic.Listener {
        weak var interactor: ChatListBusinessLogic?
        //public init() {}
        override func onInfo(info: MsgServerInfo) {
            print("Contacts got onInfo update \(String(describing: info.what))")
        }
        override func onPres(pres: MsgServerPres) {
            if pres.what == "msg" || pres.what == "off" || pres.what == "on" {
                if let name = pres.src {
                    interactor?.updateChat(name)
                }
            }
        }
        override func onMetaSub(sub: Subscription<VCard, PrivateType>) {
            // TODO: sub.pub?.constructBitmap()
            print("on meta sub")
        }
        override func onMetaDesc(desc: Description<VCard, PrivateType>) {
            // TODO: desc.pub?.constructBitmap()
            print("on meta desc")
        }
        override func onSubsUpdated() {
            // datasetChanged()
            print("on subs updated")
            interactor?.loadAndPresentTopics()
        }
        override func onContUpdate(sub: Subscription<VCard, PrivateType>) {
            // Method makes no sense in context of MeTopic.
            // throw new UnsupportedOperationException();
        }
    }

    var presenter: ChatListPresentationLogic?
    var router: ChatListRoutingLogic?
    var topics: [DefaultComTopic]?
    private var meListener: MeListener
    private var meTopic: DefaultMeTopic? = nil
    //private var meListener: DefaultMeTopic.Listener
    init() {
        meListener = MeListener()
        self.meListener.interactor = self
    }
    func attachToMeTopic() {
        let tinode = Cache.getTinode()
        do {
            try UiUtils.attachToMeTopic(meListener: self.meListener)?.then(
                onSuccess: { [weak self] msg in
                    self?.loadAndPresentTopics()
                    self?.meTopic = tinode.getMeTopic()
                    return nil
                }, onFailure: { [weak self] err in
                    print("err = ")
                    if let e = err as? TinodeError, case .serverResponseError(let code, _, _) = e {
                        if code == 404 {
                            tinode.logout()
                            self?.router?.routeToLogin()
                        }
                    }
                    return nil
                })
        } catch {
            tinode.logout()
            self.router?.routeToLogin()
        }
    }
    func cleanup() {
        self.meTopic?.listener = nil
    }
    func loadAndPresentTopics() {
        self.topics = Cache.getTinode().getFilteredTopics(filter: {(topic: TopicProto) in
            return topic.topicType.matches(TopicType.user)
        })?.map {
            // Must succeed.
            $0 as! DefaultComTopic
        }
        self.presenter?.presentTopics(self.topics ?? [])
    }

    func updateChat(_ name: String) {
        self.presenter?.updateChat(name)
    }
}
