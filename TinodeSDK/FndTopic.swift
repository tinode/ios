//
//  FndTopic.swift
//  TinodeSDK
//
//  Copyright © 2020-2025 Tinode LLC. All rights reserved.
//

import Foundation

public class FndTopic<SP: Codable>: Topic<String, String, SP, [String]> {
    init(tinode: Tinode?) {
        super.init(tinode: tinode, name: Tinode.kTopicFnd)
    }

    @discardableResult
    override public func setMeta(meta: MsgSetMeta<String, String>) -> PromisedReply<ServerMessage> {
        if self.subs != nil {
            self.subs!.removeAll()
            self.subs = nil
            self.subsLastUpdated = nil
            self.listener?.onSubsUpdated()
        }
        return super.setMeta(meta: meta)
    }

    override func routeMetaSub(meta: MsgServerMeta) {
        if let subscriptions = meta.sub {
            for upd in subscriptions {
                var sub = getSubscription(for: upd.uniqueId)
                if sub != nil {
                    _ = sub!.merge(sub: upd as! Subscription<SP, [String]>)
                } else {
                    sub = upd as? Subscription<SP, [String]>
                    self.addSubToCache(sub: sub!)
                }
                self.listener?.onMetaSub(sub: sub!)
            }
        }
        self.listener?.onSubsUpdated()
    }

    override public func getSubscriptions() -> [Subscription<SP, [String]>]? {
        guard let v = subs?.values else { return nil }
        return Array(v)
    }

    override func addSubToCache(sub: Subscription<SP, [String]>) {
        guard let unique = sub.user ?? sub.topic else { return }

        if subs == nil {
            subs = [:]
        }
        subs![unique] = sub
    }

    public func checkTagUniqueness(tag: String, caller: String) -> PromisedReply<Bool> {
        let result = PromisedReply<Bool>()

        self.subscribe(set: nil, get: nil)
            .thenApply { _ in
                return self.setMeta(pub: tag, priv: nil)
            }
            .thenApply { _ in
                return self.getMeta(query: self.metaGetBuilder().withTags().build())
            }
            .thenApply { response in
                guard let tags = response?.meta?.tags else {
                    // Unable to interpret server response, ignore the test.
                    try? result.resolve(result: true)
                    return nil
                }

                for t in tags {
                    if t != caller {
                        // Test failed
                        try? result.resolve(result: false)
                        return nil
                    }
                }
                // The gats is really unique.
                try? result.resolve(result: true)
                return nil
            }
            .thenCatch { err in
                try? result.reject(error: err)
                return nil
            }
        return result
    }
}
