//
//  PlaceholderTextView.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

// UITextView with an optional placeholder text.
@IBDesignable class PlaceholderTextView: UITextView {

    // MARK: constants

    private enum Constants {
        static let defaultPlaceholderColorLight = UIColor(red: 0, green: 0, blue: 25/255, alpha: 0.22)
        static let defaultPlaceholderColorDark = UIColor.lightGray
        static let defaultTextColorLight = UIColor.black
        static let defaultTextColorDark = UIColor.white
        static let defaultPlaceholderText = "AbCd..."
    }

    private var isShowingPlaceholder: Bool = false

    // MARK: IB variables

    @IBInspectable var placeholderText: String = Constants.defaultPlaceholderText {
        didSet {
            if isShowingPlaceholder {
                text = placeholderText
            }
        }
    }

    var mainTextColor: UIColor = Constants.defaultTextColorLight
    @IBInspectable var placeholderColor: UIColor? {
        didSet {
            if isShowingPlaceholder {
                textColor = placeholderColor
            }
        }
    }

    // MARK: overridden UITextView variables

    override var text: String! {
        didSet {
            checkForEmptyText()
        }
    }

    override var attributedText: NSAttributedString! {
        didSet {
            checkForEmptyText()
        }
    }

    // See explanation here https://stackoverflow.com/questions/13601643/uimenucontroller-hides-the-keyboard/23849955#23849955
    // and here https://github.com/alexpersian/MenuItemTester/blob/master/MenuItemTester/InputTextField.swift
    weak var nextResponderOverride: UIResponder?

    override var next: UIResponder? {
        if nextResponderOverride != nil {
            return nextResponderOverride
        } else {
            return super.next
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if nextResponderOverride != nil {
            return false
        } else {
            return super.canPerformAction(action, withSender: sender)
        }
    }

    private func setColors() {
        if traitCollection.userInterfaceStyle == .dark {
            self.mainTextColor = Constants.defaultTextColorDark
            self.placeholderColor = Constants.defaultPlaceholderColorDark
        } else {
            self.mainTextColor = Constants.defaultTextColorLight
            self.placeholderColor = Constants.defaultPlaceholderColorLight
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        setColors()
        textColor = isShowingPlaceholder ? placeholderColor : mainTextColor
    }

    // MARK: initializers

    override public init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        addTextChangeObserver()
        textEmptyHandler()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        addTextChangeObserver()
        setColors()
        textEmptyHandler()
    }

    // MARK: private methods

    private func addTextChangeObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(textBeginEditing), name: UITextView.textDidBeginEditingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(checkForEmptyText), name: UITextView.textDidEndEditingNotification, object: nil)
    }

    private func textEmptyHandler() {
        if text.isEmpty {
            isShowingPlaceholder = true
            textColor = placeholderColor ?? Constants.defaultPlaceholderColorLight
            text = placeholderText
        }
    }

    @objc private func textBeginEditing() {
        if isShowingPlaceholder {
            text = nil
            textColor = mainTextColor
            isShowingPlaceholder = false
        }
    }

    @objc private func checkForEmptyText() {
        if text.isEmpty && !isShowingPlaceholder && !isFirstResponder {
            text = placeholderText
            textColor = placeholderColor
            isShowingPlaceholder = true
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UITextView.textDidBeginEditingNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UITextView.textDidEndEditingNotification, object: nil)
    }
}
