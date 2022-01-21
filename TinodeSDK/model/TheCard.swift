//
//  TheCard.swift
//  ios
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import Foundation

public class Photo: Codable {
    public let type: String?
    // base64-encoded byte array.
    public let data: String?
    // URL of the image for out-of-band avatars
    public let ref: String?
    // Width and height of the image.
    public let width: Int?
    public let height: Int?
    // Cached decoded image (not serialized).
    private var cachedImage: UIImage?

    private enum CodingKeys: String, CodingKey {
        case type, data, ref, width, height
    }

    public init(type: String?, data: String?, width: Int? = nil, height: Int? = nil) {
        self.type = type
        self.data = data
        self.ref = nil
        self.width = width
        self.height = height
    }

    public init(type: String?, ref: String?) {
        self.type = type
        self.data = nil
        self.ref = ref
        self.width = nil
        self.height = nil
    }

    convenience public init(type: String?, data: Data?, width: Int? = nil, height: Int? = nil) {
        self.init(type: type, data: data?.base64EncodedString())
    }

    convenience public init(image: UIImage) {
        self.init(type: "image/png", data: image.pngData(), width: Int(image.size.width), height: Int(image.size.height))
    }

    public func image() -> UIImage? {
        if cachedImage == nil {
            guard let b64data = self.data else { return nil }
            guard let dataDecoded = Data(base64Encoded: b64data, options: .ignoreUnknownCharacters) else { return nil }
            cachedImage = UIImage(data: dataDecoded)
        }
        return cachedImage
    }
    public func copy() -> Photo {
        return Photo(type: self.type, data: self.data)
    }
}

public class Contact: Codable {
    var type: String?
    var uri: String?
    init() {}
    public func copy() -> Contact {
        let contactCopy = Contact()
        contactCopy.type = self.type
        contactCopy.uri = self.uri
        return contactCopy
    }
}

public class Name: Codable {
    var surname: String?
    var given: String?
    var additional: String?
    var prefix: String?
    var suffix: String?
    init() {}
    public func copy() -> Name {
        let nameCopy = Name()
        nameCopy.surname = self.surname
        nameCopy.given = self.given
        nameCopy.additional = self.additional
        nameCopy.prefix = self.prefix
        nameCopy.suffix = self.suffix
        return nameCopy
    }
}

public class Birthday: Codable {
    // Year like 1975
    var y: Int16?
    // Month 1..12.
    var m: Int8?
    // Day 1..31.
    var d: Int8?
    init() {}
    public func copy() -> Birthday {
        let copy = Birthday()
        copy.y = y
        copy.m = m
        copy.d = d
        return copy
    }
}

public class TheCard: Codable, Mergeable {
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
    public var bday: Birthday?
    // Free-form description.
    public var note: String?

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
    public func copy() -> TheCard {
        let cardCopy = TheCard(fn: fn, avatar: self.photo?.copy())
        cardCopy.n = self.n
        cardCopy.org = self.org
        cardCopy.title = self.title
        cardCopy.tel = self.tel?.map { $0 }
        cardCopy.email = self.email?.map { $0 }
        cardCopy.impp = self.impp?.map { $0 }
        cardCopy.bday = self.bday?.copy()
        cardCopy.note = self.note
        return cardCopy
    }

    public func merge(with another: Mergeable) -> Bool {
        guard let another = another as? TheCard else { return false }
        var changed = false
        if another.fn != nil {
            self.fn = !Tinode.isNull(obj: another.fn) ? another.fn : nil
            changed = true
        }
        if another.title != nil {
            self.title = !Tinode.isNull(obj: another.title) ? another.title : nil
            changed = true
        }
        if another.org != nil {
            self.org = !Tinode.isNull(obj: another.org) ? another.org : nil
            changed = true
        }
        if another.tel != nil {
            self.tel = !Tinode.isNull(obj: another.tel) ? another.tel : nil
            changed = true
        }
        if another.email != nil {
            self.email = !Tinode.isNull(obj: another.email) ? another.email : nil
            changed = true
        }
        if another.impp != nil {
            self.impp = !Tinode.isNull(obj: another.impp) ? another.impp : nil
            changed = true
        }
        if another.photo != nil {
            self.photo = !Tinode.isNull(obj: another.photo) ? another.photo!.copy() : nil
            changed = true
        }
        if another.bday != nil {
            self.bday = !Tinode.isNull(obj: another.bday) ? another.bday!.copy() : nil
            changed = true
        }
        if another.note != nil {
            self.note = !Tinode.isNull(obj: another.note) ? another.note : nil
            changed = true
        }
        return changed
    }
}
