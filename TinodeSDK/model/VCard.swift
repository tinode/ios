//
//  VCard.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation

public class Photo: Codable {
    public let type: String?
    // base64-encoded byte array.
    public let data: String?
    // Cached decoded image (not serialized).
    private var cachedImage: UIImage?

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

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
    var type: String? = nil
    var uri: String? = nil
    init() {}
    public func copy() -> Contact {
        let contactCopy = Contact()
        contactCopy.type = self.type
        contactCopy.uri = self.uri
        return contactCopy
    }
}

public class Name: Codable {
    var surname: String? = nil
    var given: String? = nil
    var additional: String? = nil
    var prefix: String? = nil
    var suffix: String? = nil
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

public class VCard: Codable, Mergeable {
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
    public func copy() -> VCard {
        let vcardCopy = VCard(
            fn: fn,
            avatar: self.photo?.copy())
        vcardCopy.n = self.n
        vcardCopy.org = self.org
        vcardCopy.title = self.title
        vcardCopy.tel = self.tel?.map { $0 }
        vcardCopy.email = self.email?.map { $0 }
        vcardCopy.impp = self.impp?.map { $0 }
        return vcardCopy
    }

    public func merge(with another: Mergeable) -> Int {
        guard another is VCard else { return 0 }
        let anotherVCard = another as! VCard
        var changed = 0
        if anotherVCard.fn != nil {
            self.fn = !Tinode.isNull(obj: anotherVCard.fn) ? anotherVCard.fn : nil
            changed += 1
        }
        if anotherVCard.title != nil {
            self.title = !Tinode.isNull(obj: anotherVCard.title) ? anotherVCard.title : nil
            changed += 1
        }
        if anotherVCard.org != nil {
            self.org = !Tinode.isNull(obj: anotherVCard.org) ? anotherVCard.org : nil
            changed += 1
        }
        if anotherVCard.tel != nil {
            self.tel = !Tinode.isNull(obj: anotherVCard.tel) ? anotherVCard.tel : nil
            changed += 1
        }
        if anotherVCard.email != nil {
            self.email = !Tinode.isNull(obj: anotherVCard.email) ? anotherVCard.email : nil
            changed += 1
        }
        if anotherVCard.impp != nil {
            self.impp = !Tinode.isNull(obj: anotherVCard.impp) ? anotherVCard.impp : nil
            changed += 1
        }
        if anotherVCard.photo != nil {
            self.photo = !Tinode.isNull(obj: anotherVCard.photo) ? anotherVCard.photo : nil
            changed += 1
        }
        return changed
    }
}
