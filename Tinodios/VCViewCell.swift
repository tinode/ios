//
//  VCViewController.swift
//  Tinodios
//
//  Copyright © 2023 Tinode LLC. All rights reserved.
//

import LiveKitClient
import UIKit

// Presents a video conferencing participant.
class VCViewCell: UICollectionViewCell {
    static let kIdentifer = "kVideoCollectionViewCell"

    var videoView = VideoView()
    var assetIdentifier: String?
    var peerNameLabel: PaddedLabel = {
        var label = PaddedLabel()
        label.topInset = 2
        label.bottomInset = 2
        label.leftInset = 8
        label.rightInset = 8
        label.cornerRadius = 8

        label.font = UIFont.preferredFont(forTextStyle: .title3)
        label.backgroundColor = .systemBackground
        label.alpha = 0.6
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.adjustsFontSizeToFitWidth = true
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.clipsToBounds = true
        self.autoresizesSubviews = true

        videoView.frame = self.bounds
        videoView.contentMode = .scaleAspectFill
        videoView.clipsToBounds = true
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(videoView)

        peerNameLabel.frame = CGRect(x: 10, y: frame.height - 34, width: frame.width - 10, height: 24)
        self.addSubview(peerNameLabel)

        // Use a random background color.
        let redColor = CGFloat(arc4random_uniform(255)) / 255.0
        let greenColor = CGFloat(arc4random_uniform(255)) / 255.0
        let blueColor = CGFloat(arc4random_uniform(255)) / 255.0
        self.backgroundColor = UIColor(red: redColor, green: greenColor, blue: blueColor, alpha: 1.0)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        videoView.track = nil
        assetIdentifier = nil
    }
}
