//
//  Types.swift
//  TinodeSDK
//
//  Copyright © 2019 Tinode. All rights reserved.
//

public protocol Mergeable {
    // Merges self with |another|.
    // Retuns the total number of modified fields.
    mutating func merge(with another: Mergeable) -> Int
}

extension String: Mergeable {
    public mutating func merge(with another: Mergeable) -> Int {
        guard another is String else { return 0 }
        self = another as! String
        return 1
    }
}

public typealias PrivateType = Dictionary<String, JSONValue>

extension PrivateType: Mergeable {
    public var comment: String? {
        get {
            if case let .string(v)? = self["comment"] {
                return v
            }
            return nil
        }
        set { self["comment"] = .string(newValue ?? Tinode.kNullValue) }
    }
    public var archived: Bool? {
        get {
            if case let .bool(v)? = self["arch"] {
                return v
            }
            return nil
        }
        set { self["arch"] = newValue != nil ? .bool(newValue!) : nil }
    }
    public mutating func merge(with another: Mergeable) -> Int {
        guard another is PrivateType else { return 0 }
        let anotherPT = another as! PrivateType
        for (k, v) in anotherPT {
            self[k] = v
        }
        return anotherPT.count
    }
}

// Topic and Subscription types.
public typealias DefaultDescription = Description<VCard, PrivateType>
public typealias DefaultSubscription = Subscription<VCard, PrivateType>
public typealias FndDescription = Description<String, String>
public typealias FndSubscription = Subscription<VCard, Array<String>>

public typealias DefaultTopic = Topic<VCard, PrivateType, VCard, PrivateType>
public typealias DefaultComTopic = ComTopic<VCard>
public typealias DefaultMeTopic = MeTopic<VCard>
public typealias DefaultFndTopic = FndTopic<VCard>
