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
    var avatarView = RoundImageView()

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
        v.image = UIImage(systemName: "speaker.slash.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .regular, scale: .default))!.withTintColor(.gray, renderingMode: .alwaysOriginal)
        v.backgroundColor = .systemBackground
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 10
        v.clipsToBounds = true
        v.isHidden = true
        return v
    }()

    var isMuted: Bool = false {
        didSet {
            mutedImage.isHidden = !isMuted
        }
    }

    // weak reference to the Participant
    public weak var participant: Participant? {
        didSet {
            guard oldValue != participant else { return }

            if let oldValue = oldValue {
                // Unlisten to events.
                oldValue.remove(delegate: self)
                videoView.track = nil
            }

            if let participant = participant {
                // Listen to events.
                participant.add(delegate: self)
                setFirstVideoTrack()

                setNeedsLayout()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.clipsToBounds = true
        self.autoresizesSubviews = true

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(avatarView)

        videoView.frame = self.bounds
        videoView.contentMode = .scaleAspectFill
        videoView.clipsToBounds = true
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(videoView)

        self.addSubview(peerNameLabel)
        self.addSubview(mutedImage)
        NSLayoutConstraint.activate([
            // Avatar view.
            avatarView.centerXAnchor.constraint(equalTo: avatarView.superview!.centerXAnchor),
            avatarView.centerYAnchor.constraint(equalTo: avatarView.superview!.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 80),
            avatarView.heightAnchor.constraint(equalToConstant: 80),
            // Peer name label.
            peerNameLabel.heightAnchor.constraint(
                equalToConstant: CGFloat(24)),
            peerNameLabel.widthAnchor.constraint(
                greaterThanOrEqualToConstant: CGFloat(30)),
            peerNameLabel.leftAnchor.constraint(equalTo: peerNameLabel.superview!.leftAnchor, constant: 10),
            peerNameLabel.bottomAnchor.constraint(equalTo: peerNameLabel.superview!.bottomAnchor, constant: -10),
            // Muted image.
            mutedImage.heightAnchor.constraint(equalToConstant: 20),
            mutedImage.widthAnchor.constraint(equalToConstant: 20),
            mutedImage.rightAnchor.constraint(equalTo: mutedImage.superview!.rightAnchor, constant: -10),
            mutedImage.topAnchor.constraint(equalTo: mutedImage.superview!.topAnchor, constant: 10)
        ])

        self.backgroundColor = .systemBackground
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        participant = nil
        videoView.track = nil
        videoView.isHidden = true
        assetIdentifier = nil
    }

    private func setFirstVideoTrack() {
        let track = participant?.videoTracks.first?.track as? VideoTrack
        self.videoView.track = track
        videoView.isHidden = track == nil
    }
}

extension VCViewCell: ParticipantDelegate {
    func participant(_ participant: RemoteParticipant, didSubscribe publication: RemoteTrackPublication, track: Track) {
        DispatchQueue.main.async { [weak self] in
            self?.setFirstVideoTrack()
        }
    }

    func participant(_ participant: RemoteParticipant, didUnsubscribe publication: RemoteTrackPublication, track: Track) {
        DispatchQueue.main.async { [weak self] in
            self?.setFirstVideoTrack()
        }
    }

    func participant(_ participant: Participant, didUpdate speaking: Bool) {
        DispatchQueue.main.async {
            let anim = CABasicAnimation(keyPath: "borderColor")
            anim.fromValue = UIColor.clear.cgColor
            anim.toValue = UIColor.red.cgColor
            self.layer.borderColor = UIColor.clear.cgColor
            anim.duration = CATransaction.animationDuration()
            self.layer.add(anim, forKey: "speaking")

            let anim2 = CABasicAnimation(keyPath: "borderWidth")
            anim2.fromValue = 0
            anim2.toValue = 4
            anim2.duration = CATransaction.animationDuration()
            self.layer.add(anim2, forKey: "speaking-width")
        }
    }

    func participant(_ participant: Participant, didUpdate publication: TrackPublication, muted: Bool) {
        switch publication.kind {
        case .audio:
            DispatchQueue.main.async { self.isMuted = muted }
        case .video:
            DispatchQueue.main.async { self.videoView.isHidden = muted }
        case .none:
            break
        }
    }
}
