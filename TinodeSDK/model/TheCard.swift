//
//  TheCard.swift
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import Foundation

public class Photo: Codable {
    public static let kDefaultType = "png"

    // The specific part of the image mime type, e.g. if mime type is "image/png", the type is "png".
    public let type: String?
    // Image bits.
    public let data: Data?
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

    public init(type tp: String = Photo.kDefaultType, data: Data?, ref: String?, width: Int? = nil, height: Int? = nil) {
        // Extract specific part from the full mime type.
        let parts = tp.components(separatedBy: "/")
        if parts.count > 1 {
            if parts[0] == "image" {
                // Drop the first component "image/", keep the rest.
                self.type = parts[1..<parts.count].joined(separator: "/")
            } else {
                // Invalid mime type, use default value.
                self.type = Photo.kDefaultType
            }
        } else {
            self.type = tp
        }

        self.data = data
        self.ref = ref
        self.width = width
        self.height = height
    }

    convenience public init(type: String = Photo.kDefaultType, ref: String?) {
        self.init(type: type, data: nil, ref: ref, width: nil, height: nil)
    }

    convenience public init(image: UIImage) {
        self.init(type: Photo.kDefaultType, data: image.pngData(), ref: nil, width: Int(image.size.width), height: Int(image.size.height))
        self.cachedImage = image
    }

    public var image: UIImage? {
        if cachedImage == nil {
            guard let data = self.data else { return nil }
            cachedImage = UIImage(data: data)
        }
        return cachedImage
    }

    public func copy() -> Photo {
        let copy = Photo(type: self.type ?? Photo.kDefaultType, data: self.data, ref: self.ref, width: self.width, height: self.height)
        copy.cachedImage = self.cachedImage
        return copy
    }
}

public class Organization: Codable {
    var fn: String?
    var title: String?
    init() {}
    public func copy() -> Organization {
        let copy = Organization()
        copy.fn = self.fn
        copy.title = self.title
        return copy
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
    public var org: Organization?
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

    private enum CodingKeys: String, CodingKey {
        case fn, n, org, tel, email, impp, photo, bday, note
    }

    public init() {}

    public init(fn: String?, avatar: Photo?, note: String? = nil) {
        self.fn = fn
        self.photo = avatar
        self.note = note
    }

    public init(fn: String?) {
        self.fn = fn

    }

    public init(fn: String?, avatar: UIImage?, note: String? = nil) {
        self.fn = fn
        self.note = note

        guard let avatar = avatar else { return }
        self.photo = Photo(image: avatar)
    }

    public func copy() -> TheCard {
        let copy = TheCard(fn: fn, avatar: self.photo?.copy())
        copy.n = self.n
        copy.org = self.org?.copy()
        copy.tel = self.tel?.map { $0 }
        copy.email = self.email?.map { $0 }
        copy.impp = self.impp?.map { $0 }
        copy.bday = self.bday?.copy()
        copy.note = self.note
        return copy
    }

    public var photoRefs: [String]? {
        guard let ref = photo?.ref else { return nil }
        return [ref]
    }

    public var photoBits: Data? {
        return photo?.data
    }

    public var photoMimeType: String {
        return "image/\(photo?.type ?? Photo.kDefaultType)"
    }

    public func merge(with another: Mergeable) -> Bool {
        guard let another = another as? TheCard else { return false }
        var changed = false
        if another.fn != nil {
            self.fn = !Tinode.isNull(obj: another.fn) ? another.fn : nil
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
