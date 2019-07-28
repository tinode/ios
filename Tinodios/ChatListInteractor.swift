//
//  ChatListInteractor.swift
//  Tinodios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation
import UIKit
import TinodeSDK

protocol ChatListBusinessLogic: class {
    func loadAndPresentTopics()
    func attachToMeTopic()
    func leaveMeTopic()
    func updateChat(_ name: String)
    func setup()
    func cleanup()
    func deleteTopic(_ name: String)
    func changeArchivedStatus(forTopic name: String, archived: Bool)
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
            if pres.what == "msg" {
                interactor?.loadAndPresentTopics()
            } else if pres.what == "off" || pres.what == "on" {
                if let name = pres.src {
                    interactor?.updateChat(name)
                }
            }
        }
        override func onMetaSub(sub: Subscription<VCard, PrivateType>) {
            // TODO: sub.pub?.constructBitmap()
            print("on meta sub")
            if Tinode.topicTypeByName(name: sub.topic) == .p2p {
                ContactsManager.default.processSubscription(sub: sub)
            }
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
    private class ChatEventListener: UiTinodeEventListener {
        private weak var interactor: ChatListBusinessLogic?
        init(interactor: ChatListBusinessLogic?, viewController: UIViewController?, connected: Bool) {
            super.init(viewController: viewController, connected: connected)
            self.interactor = interactor
        }
        override func onLogin(code: Int, text: String) {
            super.onLogin(code: code, text: text)
            self.interactor?.attachToMeTopic()
        }
        override func onDisconnect(byServer: Bool, code: Int, reason: String) {
            super.onDisconnect(byServer: byServer, code: code, reason: reason)
            // Update presence indicators (all should be off).
            self.interactor?.loadAndPresentTopics()
        }
    }

    var presenter: ChatListPresentationLogic?
    var router: ChatListRoutingLogic?
    var topics: [DefaultComTopic]?
    private var archivedTopics: [DefaultComTopic]?
    private var meListener: MeListener? = nil
    private var meTopic: DefaultMeTopic? = nil
    private var tinodeEventListener: ChatEventListener? = nil

    func attachToMeTopic() {
        let tinode = Cache.getTinode()
        guard meTopic == nil || !meTopic!.attached else {
            return
        }
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
    func leaveMeTopic() {
        if self.meTopic?.attached ?? false {
            self.meTopic?.leave()
        }
    }
    func setup() {
        if self.meListener == nil {
            self.meListener = MeListener()
        }
        self.meListener?.interactor = self
        self.meTopic?.listener = meListener
        let tinode = Cache.getTinode()
        if self.tinodeEventListener == nil {
            self.tinodeEventListener = ChatEventListener(
                interactor: self,
                viewController: self.presenter?.underlyingViewController,
                connected: tinode.isConnected)
        }
        tinode.listener = self.tinodeEventListener
    }
    func cleanup() {
        if self.meTopic?.listener === self.meListener {
            self.meTopic?.listener = nil
        }
        let tinode = Cache.getTinode()
        if tinode.listener === self.tinodeEventListener {
            tinode.listener = nil
        }
    }
    private func getTopics(archived: Bool) -> [DefaultComTopic]? {
        return Cache.getTinode().getFilteredTopics(filter: {(topic: TopicProto) in
            return topic.topicType.matches(TopicType.user) && topic.isArchived == archived
        })?.map {
            // Must succeed.
            $0 as! DefaultComTopic
        }
    }
    func loadAndPresentTopics() {
        self.topics = self.getTopics(archived: false)
        self.archivedTopics = self.getTopics(archived: true)
        self.presenter?.presentTopics(
            self.topics ?? [], archivedTopics: self.archivedTopics)
    }

    func updateChat(_ name: String) {
        self.presenter?.topicUpdated(name)
    }

    func deleteTopic(_ name: String) {
        let topic = Cache.getTinode().getTopic(topicName: name) as! DefaultComTopic
        do {
            try topic.delete()?.then(onSuccess: { [weak self] msg in
                self?.loadAndPresentTopics()
                return nil
            })
        } catch {
            print(error)
        }
    }

    func changeArchivedStatus(forTopic name: String, archived: Bool) {
        let topic = Cache.getTinode().getTopic(topicName: name) as! DefaultComTopic
        do {
            try topic.updateArchived(archived: archived)?.then(onSuccess: { [weak self] msg in
                self?.loadAndPresentTopics()
                return nil
            })
        } catch {
            print(error)
        }
    }
}
