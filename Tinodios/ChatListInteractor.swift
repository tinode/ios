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
                print("one chat changed " + (pres.src ?? "nil"))
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
    //private var meListener: DefaultMeTopic.Listener
    init() {
        meListener = MeListener()
        self.meListener.interactor = self
    }
    func attachToMeTopic() {
        let tinode = Cache.getTinode()
        var me = tinode.getMeTopic()
        if me == nil  {
            //let t: DefaultMeTopic.Listener = self.meListener
            //let q = DefaultMeTopic.Listener()
            me = DefaultMeTopic(tinode: tinode, l: meListener)
            //me = try! DefaultMeTopic(tinode: tinode, l: q)
            //let z = try? DefaultMeTopic(tinode: tinode, l: nil)
                                     //l: meListener as DefaultMeTopic.Listener)
        } else {
            me!.listener = meListener
        }
        let get = me!.getMetaGetBuilder().withGetDesc().withGetSub().build()
        let _ = try? me!.subscribe(set: nil, get: get).then(
            onSuccess: { [weak self] msg in
                self?.loadAndPresentTopics()
                return nil
            },
            onFailure: { [weak self] err in
                print("err = ")
                if let e = err as? TinodeError, case .serverResponseError(let code, _, _) = e {
                    if code == 404 {
                        tinode.logout()
                        self?.router?.routeToLogin()
                    }
                }
                return nil
        })
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
