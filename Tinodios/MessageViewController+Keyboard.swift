//
//  MessageViewController+Keyboard.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

extension MessageViewController {

    func addKeyboardObservers() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            self,
            selector: #selector(adjustForKeyboard(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil)
        notificationCenter.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil)
    }

    @objc func adjustForKeyboard(_ notification: Notification) {
        // Apparently there is a bug in iOS 11 on iPad which sends useless notifications. This is a workaround.
        guard
            let keyboardInfo = KeyboardInfo(notification: notification),
            !keyboardInfo.frameBegin.isEmpty
        else { return }

        let change: CGFloat = keyboardInfo.frameEnd.height
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: change, right: 0)
        let inputAccessoryViewHeight = inputAccessoryView?.frame.height ?? 0

        let overlap: CGFloat
        // Try to use frameBegin and frameEnd, when all available content is taller
        // than viewport less send bar. This can be done only on newer iOS versions.
        if collectionView.contentSize.height > collectionView.bounds.height - inputAccessoryViewHeight {
            overlap = keyboardInfo.frameEnd.height - keyboardInfo.frameBegin.height
        } else {
            overlap =
                collectionView.contentSize.height
                - collectionView.contentOffset.y
                - keyboardInfo.frameEnd.origin.y
                // 2x because keyboardInfo.frameEnd.origin.y accounts for inputAccessoryViewHeight
                + 2 * inputAccessoryViewHeight
        }

        if overlap > 0 && keyboardInfo.frameEnd.size.height != inputAccessoryViewHeight {
            let contentOffset = CGPoint(
                x: collectionView.contentOffset.x,
                y: collectionView.contentOffset.y + overlap)
            collectionView.setContentOffset(contentOffset, animated: false)
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        collectionView.contentInset.bottom = inputAccessoryView?.frame.height ?? 0
    }

    private var bottomInset: CGFloat {
        return collectionView.adjustedContentInset.bottom - collectionView.contentInset.bottom
    }
}
