//
//  AvatarWithOnlineIndicator.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

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

    public func set(icon: UIImage?, title: String?, id: String?, online: Bool) {
        self.avatar.set(icon: icon, title: title, id: id)
        self.online.backgroundColor = online ?
            UIColor.init(fromHexCode: 0xFF40C040) : UIColor.init(fromHexCode: 0xFFE0E0E0)
    }
}
