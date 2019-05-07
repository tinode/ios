//
//  MessageViewController+Keyboard.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

extension MessageViewController {

    func addKeyboardObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(adjustForKeyboard), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(adjustForKeyboard), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UITextView.keyboardWillHideNotification, object: nil)
    }

    @objc func adjustForKeyboard(notification: Notification) {
        // Apparently there is a bug in iOS 11 on iPad which sends useless notifications. This is a workaround.
        guard let keyboardScreenStart = notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect else { return }
        guard !keyboardScreenStart.isEmpty else { return }

        guard let keyboardValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        let keyboardScreenEndFrame = keyboardValue.cgRectValue
        let keyboardViewEndFrame = view.convert(keyboardScreenEndFrame, from: view.window)

        if notification.name == UIResponder.keyboardWillHideNotification {
            collectionView.contentInset = .zero
        } else {
            let change: CGFloat
            if #available(iOS 11.0, *) {
                change = keyboardViewEndFrame.height - view.safeAreaInsets.bottom
            } else {
                change = keyboardViewEndFrame.height
            }

            collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: change, right: 0)
        }
        // Inset of the same size as the keyboard minus the bottom safe area inset.
        collectionView.scrollIndicatorInsets = self.collectionView.contentInset

        // How much do we need to scroll up to maintain the same scroll position relative to the bottom of the view
        let contentBottom = collectionView.frame.origin.y + collectionView.contentSize.height - collectionView.contentOffset.y
        let overlap = contentBottom - keyboardViewEndFrame.origin.y

        // Scroll the view to maintain the current position.
        if overlap > 0 {
            let contentOffset = CGPoint(x: collectionView.contentOffset.x, y: collectionView.contentOffset.y + overlap)
            collectionView.setContentOffset(contentOffset, animated: false)
        }
    }

    private var bottomInset: CGFloat {
        if #available(iOS 11.0, *) {
            return collectionView.adjustedContentInset.bottom - collectionView.contentInset.bottom
        } else {
            return 0
        }
    }
}
