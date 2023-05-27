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
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    var mutedImage: UIImageView = {
        var v = UIImageView()
        v.alpha = 0.6
        v.image = UIImage(systemName: "speaker.slash.fill")
        v.backgroundColor = .systemBackground
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    var isMuted: Bool = false {
        didSet {
            mutedImage.isHidden = !isMuted
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.clipsToBounds = true
        self.autoresizesSubviews = true

        videoView.frame = self.bounds
        videoView.contentMode = .scaleAspectFill
        videoView.clipsToBounds = true
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(videoView)

        self.addSubview(peerNameLabel)
        self.addSubview(mutedImage)
        NSLayoutConstraint.activate([
            peerNameLabel.heightAnchor.constraint(
                equalToConstant: CGFloat(24)),
            peerNameLabel.widthAnchor.constraint(
                greaterThanOrEqualToConstant: CGFloat(30)),
            peerNameLabel.leftAnchor.constraint(equalTo: peerNameLabel.superview!.leftAnchor, constant: 10),
            peerNameLabel.bottomAnchor.constraint(equalTo: peerNameLabel.superview!.bottomAnchor, constant: -10),
            mutedImage.heightAnchor.constraint(equalToConstant: 20),
            mutedImage.widthAnchor.constraint(equalToConstant: 20),
            mutedImage.rightAnchor.constraint(equalTo: mutedImage.superview!.rightAnchor, constant: -10),
            mutedImage.topAnchor.constraint(equalTo: mutedImage.superview!.topAnchor, constant: 10)
        ])

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
