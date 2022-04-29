//
//  EntityTextAttachment.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import TinodeSDK
import UIKit

public protocol EntityTextAttachmentDelegate: AnyObject {
    func action(value: URL, fromEntityKey: Int)
}

public class EntityTextAttachment: NSTextAttachment {
    public var draftyEntityKey: Int?
    public var type: String?
    public var delegate: EntityTextAttachmentDelegate?
}
