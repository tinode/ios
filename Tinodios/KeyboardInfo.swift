//
//  KeyboardInfo.swift
//  Tinodios
//
//  Created by Nikita Timonin on 24/11/2019.
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

struct KeyboardInfo {

    let frameBegin: CGRect
    let frameEnd: CGRect
    let isLocal: Bool
    let animationDuration: TimeInterval
    let animationCurve: UIView.AnimationCurve

    init?(notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let frameBegin = userInfo[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect,
            let frameEnd = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let isLocal = userInfo[UIResponder.keyboardIsLocalUserInfoKey] as? Bool,
            let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
            let rawCurve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
            let animationCurve = UIView.AnimationCurve(rawValue: rawCurve)
            else { return nil }

        self.frameBegin = frameBegin
        self.frameEnd = frameEnd
        self.isLocal = isLocal
        self.animationDuration = animationDuration
        self.animationCurve = animationCurve
    }

    var animationOptions: UIView.AnimationOptions {
        let option = animationCurve.rawValue << 16
        return UIView.AnimationOptions(rawValue: UInt(option))
    }
}
