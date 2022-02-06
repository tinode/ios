//
//  AvatarWithOnlineIndicator.swift
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK

class AvatarWithOnlineIndicator: UIView {
    @IBOutlet var contentView: UIView!
    @IBOutlet weak var avatar: RoundImageView!
    @IBOutlet weak var online: UIView!

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
    public func setOnline(online: Bool?) {
        guard let online = online else {
            self.online.isHidden = true
            return
        }
        self.online.isHidden = false
        self.online.backgroundColor = online ?
            UIColor.init(fromHexCode: 0xFF40C040) : UIColor.init(fromHexCode: 0xFFE0E0E0)
    }
    public func set(pub: TheCard?, id: String?, online: Bool?) {
        self.avatar.set(pub: pub, id: id)
        self.setOnline(online: online)
    }
}
