//
//  VCard.swift
//  ios
//
//  Copyright © 2018 Tinode. All rights reserved.
//

import Foundation

public class Photo: Codable {
    public let type: String?
    // Byte array.
    public let data: String?

    public init(type: String?, data: String?) {
        self.type = type
        self.data = data
    }

    convenience public init(type: String?, data: Data?) {
        self.init(type: type, data: data?.base64EncodedString())
    }

    convenience public init(image: UIImage) {
        self.init(type: "image/png", data: image.pngData())
    }
}

public class Contact: Codable {
    let type: String?
    let uri: String?
}

public class Name: Codable {
    let surname: String?
    let given: String?
    let additional: String?
    let prefix: String?
    let suffix: String?
}

public class VCard: Codable {
    public var fn: String?
    public var n: Name?
    public var org: String?
    public var title: String?
    // List of phone numbers associated with the contact.
    public var tel: [Contact]?
    // List of contact's email addresses.
    public var email: [Contact]?
    public var impp: [Contact]?
    // Avatar photo.
    public var photo: Photo?
    
    public init(fn: String?, avatar: Photo?) {
        self.fn = fn
        self.photo = avatar
    }

    public init(fn: String?, avatar: Data?) {
        self.fn = fn
        guard let avatar = avatar else { return }
        self.photo = Photo(type: nil, data: avatar)
    }

    public init(fn: String?, avatar: UIImage?) {
        self.fn = fn

        guard let avatar = avatar else { return }
        self.photo = Photo(image: avatar)
    }
}
