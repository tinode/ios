//
//  AvatarWithOnlineIndicator+TypingAnimation.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit

extension AvatarWithOnlineIndicator {
    static let kTypingAnimationSize = 4
    static let kAnimationColorSequence = [
        UIColor(fromHexCode: 0xFF40C040),
        UIColor(fromHexCode: 0xFF30D030),
        UIColor(fromHexCode: 0xFF10EE10),
        UIColor(fromHexCode: 0xFF00FF00)
    ]
    // Runs typing animation over the online indicator
    // every 1/20th of a second |steps| times.
    func presentTypingAnimation(steps: Int) {
        guard 1..<100 ~= steps else {
            fatalError("Steps must be between 0 and 100.")
        }
        // Note that we can do it (there will be no race condition),
        // since UI thread synchronizes this write and possibly
        // other reads/write triggered by timer.
        self.tag = steps
        guard self.onlineIndicator.subviews.isEmpty else {
            // If we are already presenting another typing animation,
            // setting tag to |steps| will increase its duration.
            return
        }
        // Add animation view on top of the online indicator.
        let animation = UIView(frame: CGRect(x: 0, y: 0, width: AvatarWithOnlineIndicator.kTypingAnimationSize, height: AvatarWithOnlineIndicator.kTypingAnimationSize))
        // Rounded corners.
        animation.layer.cornerRadius = CGFloat(AvatarWithOnlineIndicator.kTypingAnimationSize / 2)
        animation.layer.masksToBounds = true
        self.onlineIndicator.addSubview(animation)
        // Place it in the center of the online indicator.
        animation.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            animation.heightAnchor.constraint(
                equalToConstant: CGFloat(AvatarWithOnlineIndicator.kTypingAnimationSize)),
            animation.widthAnchor.constraint(
                equalToConstant: CGFloat(AvatarWithOnlineIndicator.kTypingAnimationSize)),
            animation.centerXAnchor.constraint(equalTo: animation.superview!.centerXAnchor),
            animation.centerYAnchor.constraint(equalTo: animation.superview!.centerYAnchor)
        ])
        _ = Timer.scheduledTimer(
            timeInterval: 0.05,  // 1/20th of a second.
            target: self,
            selector: #selector(animationStep),
            userInfo: nil,
            repeats: true)
    }
    @objc private func animationStep(timer: Timer) {
        guard !self.onlineIndicator.subviews.isEmpty else {
            timer.invalidate()
            return
        }
        let animationView = self.onlineIndicator.subviews[0]
        animationView.backgroundColor =
            AvatarWithOnlineIndicator.kAnimationColorSequence[
                self.tag % AvatarWithOnlineIndicator.kAnimationColorSequence.count]
        self.tag -= 1
        if self.tag <= 0 {
            timer.invalidate()
            animationView.removeFromSuperview()
        }
    }
}
