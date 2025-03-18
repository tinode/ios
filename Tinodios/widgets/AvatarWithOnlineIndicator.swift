//
//  AvatarWithOnlineIndicator.swift
//
//  Copyright © 2019-2025 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK

class AvatarWithOnlineIndicator: UIView {
    static let kOnlineColor = UIColor.init(fromHexCode: 0xFF40C040)
    static let kOfflineColor = UIColor.init(fromHexCode: 0xFFE0E0E0)

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var avatar: RoundImageView!
    @IBOutlet weak var onlineIndicator: UIView!
    @IBOutlet weak var deletedIndicator: UIImageView!

    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        loadNib()
    }

    private func loadNib() {
        Bundle.main.loadNibNamed("AvatarWithOnlineIndicator", owner: self, options: nil)
        addSubview(contentView)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    /// Three states: true (show green dot), false (gray dot), nil (no dot).
    public var online: Bool? {
        didSet {
            if deleted {
                self.onlineIndicator.isHidden = true
                return
            }

            guard let online = online else {
                self.onlineIndicator.isHidden = true
                return
            }
            self.deletedIndicator.isHidden = true
            self.onlineIndicator.isHidden = false
            self.onlineIndicator.backgroundColor = online ? AvatarWithOnlineIndicator.kOnlineColor : AvatarWithOnlineIndicator.kOfflineColor
        }
    }

    /// Three states: true (show green dot), false (gray dot), nil (no dot).
    public var deleted: Bool = false {
        didSet {
            if deleted {
                self.deletedIndicator.isHidden = false
                self.onlineIndicator.isHidden = true
            } else {
                self.deletedIndicator.isHidden = true
                self.onlineIndicator.isHidden = false
            }
        }
    }

    public func set(pub: TheCard?, id: String?, online: Bool?, deleted: Bool) {
        self.avatar.set(pub: pub, id: id, deleted: deleted)
        if online != nil {
            self.onlineIndicator.isHidden = false
            self.onlineIndicator.backgroundColor = online! ? AvatarWithOnlineIndicator.kOnlineColor : AvatarWithOnlineIndicator.kOfflineColor
        } else {
            self.onlineIndicator.isHidden = true
        }

        self.deletedIndicator.isHidden = !deleted
    }
}
