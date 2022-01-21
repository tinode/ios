//
//  Types.swift
//  TinodeSDK
//
//  Copyright © 2019 Tinode. All rights reserved.
//

public protocol Mergeable {
    // Merges self with |another|.
    // Retuns true if the target object was modified.
    mutating func merge(with another: Mergeable) -> Bool
}

extension String: Mergeable {
    public mutating func merge(with another: Mergeable) -> Bool {
        guard another is String else { return false }
        self = another as! String
        return true
    }
}

public typealias PrivateType = [String: JSONValue]

extension PrivateType: Mergeable {
    public func getBoolValue(name: String) -> Bool? {
        if case let .bool(v) = self[name] {
            return v
        }
        return nil
    }
    public func getStringValue(name: String) -> String? {
        if case let .string(v) = self[name] {
            return v
        }
        return nil
    }

    public var comment: String? {
        get {
            return getStringValue(name: "comment")
        }
        set {
            self["comment"] = .string(newValue ?? Tinode.kNullValue)
        }
    }
    public var archived: Bool? {
        get {
            return getBoolValue(name: "arch")
        }
        set {
            self["arch"] = newValue != nil ? .bool(newValue!) : nil
        }
    }
    public mutating func merge(with another: Mergeable) -> Bool {
        guard another is PrivateType else { return false }
        let anotherPT = another as! PrivateType
        for (k, v) in anotherPT {
            self[k] = v
        }
        return !anotherPT.isEmpty
    }
}

public typealias TrustedType = [String: JSONValue]

extension TrustedType {
    public var isVerified: Bool? {
        return getBoolValue(name: "verified")
    }
    public var isStaffManaged: Bool? {
        return getBoolValue(name: "staff")
    }
    public var isDangerous: Bool? {
        return getBoolValue(name: "danger")
    }
}

// Topic and Subscription types.
public typealias DefaultDescription = Description<TheCard, PrivateType>
public typealias DefaultSubscription = Subscription<TheCard, PrivateType>
public typealias FndDescription = Description<String, String>
public typealias FndSubscription = Subscription<TheCard, [String]>

public typealias DefaultTopic = Topic<TheCard, PrivateType, TheCard, PrivateType>
public typealias DefaultComTopic = ComTopic<TheCard>
public typealias DefaultMeTopic = MeTopic<TheCard>
public typealias DefaultFndTopic = FndTopic<TheCard>
