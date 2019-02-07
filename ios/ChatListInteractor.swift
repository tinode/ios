//
//  ChatListAdapter.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import UIKit

protocol ChatListBusinessLogic: class {
    func loadAndPresentTopics()
    func attachToMeTopic()
}

protocol ChatListDataStore: class {
    var topics: [DefaultComTopic]? { get set }
}

class ChatListInteractor: ChatListBusinessLogic, ChatListDataStore {
    private class MeListener: DefaultMeTopic.Listener {
        weak var interactor: ChatListBusinessLogic?
        override func onInfo(info: MsgServerInfo) {
            print("Contacts got onInfo update \(String(describing: info.what))")
        }
        override func onPres(pres: MsgServerPres) {
            if pres.what == "msg" || pres.what == "off" || pres.what == "on" {
                //datasetChanged()
                print("dataset changed")
                //adapter?.update()
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
    init() {
        meListener = MeListener()
        self.meListener.interactor = self
    }
    func attachToMeTopic() {
        let tinode = Cache.getTinode()
        var me = tinode.getMeTopic()
        if me == nil  {
            me = try! DefaultMeTopic(tinode: tinode, l: meListener)
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
        self.topics = Cache.getTinode().getFilteredTopics(type: .user, updated: nil)?.map {
            // Must succeed.
            $0 as! DefaultComTopic
        }
        self.presenter?.presentTopics(self.topics ?? [])
    }
}
