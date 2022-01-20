//
//  ContactViewCell.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

protocol ContactViewCellDelegate: AnyObject {
    func selected(from: UITableViewCell)
}

class ContactViewCell: UITableViewCell {
    private static let kSelectedBackgroundColor = UIColor(red: 0xC2/255, green: 0xC9/255, blue: 0xF9/255, alpha: 0.5)
    private static let kNormalBackgroundColor = UIColor.clear

    public weak var delegate: ContactViewCellDelegate?

    @IBOutlet weak var avatar: RoundImageView!
    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var subtitle: UILabel!
    @IBOutlet var statusLabels: [ContactViewCellStatusLabel]!

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        if selected {
            delegate?.selected(from: self)
        }
    }
}

class ContactViewCellStatusLabel: PaddedLabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        let insets = super.textInsets
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }
}
