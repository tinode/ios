//
//  TagsEditView.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//
//  Based on https://github.com/whitesmith/WSTagsField.

import Foundation
import UIKit

internal struct Constants {
    internal static let kTagSelectedColor: UIColor = .gray
    internal static let kTagSelectedTextColor: UIColor = .black
    internal static let kTagTextColor: UIColor = .white
    internal static let kTagCornerRadius: CGFloat = 3.0

    internal static let kTagEditViewTextfieldHSpace: CGFloat = 3.0
    internal static let kTagEditViewMinTextfieldWidth: CGFloat = 56.0
    internal static let kTagEditViewStandardRowHeight: CGFloat = 25.0
    internal static let kTagEditViewContentInsets = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
    internal static let kTagEditViewSpaceBetweenTags: CGFloat = 2.0
    internal static let kTagEditViewSpaceBetweenLines: CGFloat = 2.0
    internal static let kTagEditViewMarginLayouts = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
}

public typealias TinodeTag = String

@IBDesignable
public class TagView: UIView {
    fileprivate let textLabel = UILabel()

    public var displayTag: TinodeTag = ""

    internal var onDidRequestDelete: ((_ tagView: TagView, _ replacementText: String?) -> Void)?
    internal var onDidRequestSelection: ((_ tagView: TagView) -> Void)?
    internal var onDidInputText: ((_ tagView: TagView, _ text: String) -> Void)?

    public var selected: Bool = false {
        didSet {
            if selected && !isFirstResponder {
                _ = becomeFirstResponder()
            } else
                if !selected && isFirstResponder {
                    _ = resignFirstResponder()
            }
            updateColors()
        }
    }

    public init(tag: TinodeTag, usingFont font: UIFont?) {
        super.init(frame: CGRect.zero)
        self.backgroundColor = tintColor
        self.layer.cornerRadius = Constants.kTagCornerRadius
        self.layer.masksToBounds = true

        textLabel.frame = CGRect(x: layoutMargins.left, y: layoutMargins.top, width: 0, height: 0)
        textLabel.font = font
        textLabel.textColor = Constants.kTagTextColor
        textLabel.backgroundColor = .clear
        addSubview(textLabel)

        self.displayTag = tag
        updateLabelText()

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGestureRecognizer))
        addGestureRecognizer(tapRecognizer)
        setNeedsLayout()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        assert(false, "Not implemented")
    }

    fileprivate func updateColors() {
        self.backgroundColor = selected ? Constants.kTagSelectedColor : tintColor
        textLabel.textColor = selected ? Constants.kTagSelectedTextColor : Constants.kTagTextColor
    }

    private var layoutMarginsHorizontal: CGFloat {
        get { return layoutMargins.left + layoutMargins.right }
    }
    private var layoutMarginsVertical: CGFloat {
        get { return layoutMargins.top + layoutMargins.bottom}
    }
    // MARK: - Size Measurements
    public override var intrinsicContentSize: CGSize {
        let labelSize = textLabel.intrinsicContentSize
        return CGSize(
            width: labelSize.width + layoutMarginsHorizontal,
            height: labelSize.height + layoutMarginsVertical)
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fittingSize = CGSize(width: size.width - layoutMarginsHorizontal,
                                 height: size.height - layoutMarginsVertical)
        let labelSize = textLabel.sizeThatFits(fittingSize)
        return CGSize(width: labelSize.width + layoutMarginsHorizontal,
                      height: labelSize.height + layoutMarginsVertical)
    }

    public func sizeToFit(_ size: CGSize) -> CGSize {
        if intrinsicContentSize.width > size.width {
            return CGSize(width: size.width,
                          height: intrinsicContentSize.height)
        }
        return intrinsicContentSize
    }

    // MARK: - Attributed Text
    fileprivate func updateLabelText() {
        textLabel.text = displayTag
        // Expand Label
        let intrinsicSize = self.intrinsicContentSize
        frame = CGRect(x: 0, y: 0,
                       width: intrinsicSize.width, height: intrinsicSize.height)
    }

    // MARK: - Laying out
    public override func layoutSubviews() {
        super.layoutSubviews()
        textLabel.frame = bounds.inset(by: layoutMargins)
        if frame.width == 0 || frame.height == 0 {
            frame.size = self.intrinsicContentSize
        }
    }

    // MARK: - First Responder (needed to capture keyboard)
    public override var canBecomeFirstResponder: Bool {
        return true
    }

    public override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        selected = true
        return didBecomeFirstResponder
    }

    public override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        selected = false
        return didResignFirstResponder
    }

    // MARK: - Gesture Recognizers
    @objc func handleTapGestureRecognizer(_ sender: UITapGestureRecognizer) {
        if selected {
            return
        }
        onDidRequestSelection?(self)
    }
}

extension TagView: UIKeyInput {
    public var hasText: Bool {
        return true
    }

    public func insertText(_ text: String) {
        onDidInputText?(self, text)
    }

    public func deleteBackward() {
        onDidRequestDelete?(self, nil)
    }
}

@IBDesignable
public class TagsEditView: UIScrollView {
    private class TagsTextField: UITextField {
        var onDeleteBackwards: (() -> Void)?

        override func deleteBackward() {
            onDeleteBackwards?()
            super.deleteBackward()
        }
    }

    private let textField = TagsTextField()

    /// Max number of lines of tags can display in TagsEditView before its contents
    /// become scrollable. Default value is 0, which means TagsEditView always
    /// resize to fit all tags.
    public var numberOfLines: Int = 1 {
        didSet {
            repositionViews()
        }
    }

    @IBInspectable
    public var placeholder: String = "" {
        didSet {
            updatePlaceholderTextVisibility()
        }
    }

    // Font used to draw the text in the tag.
    private var tagFont: UIFont?

    @IBInspectable
    public var fontSize: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize {
        didSet {
            textField.font = textField.font?.withSize(self.fontSize)
        }
    }

    @IBInspectable
    public var borderStyle: Int = 3 { // 3 is UITextField.BorderStyle.roundedRect
        didSet {
            textField.borderStyle = UITextField.BorderStyle(rawValue: self.borderStyle) ?? .roundedRect
        }
    }

    public override var isFirstResponder: Bool {
        guard !super.isFirstResponder, !textField.isFirstResponder else {
            return true
        }
        for i in 0..<tagViews.count where tagViews[i].isFirstResponder {
            return true
        }
        return false
    }

    internal var tagViews = [TagView]()

    // MARK: - Events

    /// Called when the text field should return.
    public var onShouldAcceptTag: ((TagsEditView) -> Bool)?

    /// Called before a tag is added to the tag list. Here you return false to discard tags you do not want to allow.
    public var onValidateTag: ((TinodeTag) -> Bool)?

    /**
     * Called when the user attempts to press the Return key with text partially typed.
     * @return A Tag for a match (typically the first item in the matching results),
     * or nil if the text shouldn't be accepted.
     */
    public var onVerifyTag: ((TagsEditView, _ text: String) -> Bool)?

    // MARK: - Properties

    public var preferredMaxLayoutWidth: CGFloat {
        return bounds.width
    }

    public override var intrinsicContentSize: CGSize {
        return CGSize(width: self.frame.size.width,
                      height: min(maxHeightBasedOnNumberOfLines, calculateContentHeight(layoutWidth: preferredMaxLayoutWidth) + contentInset.top + contentInset.bottom))
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        return .init(width: size.width, height: calculateContentHeight(layoutWidth: size.width) + contentInset.top + contentInset.bottom)
    }

    // MARK: -
    public override init(frame: CGRect) {
        super.init(frame: frame)
        internalInit()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        internalInit()
    }

    public override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        tagViews.forEach { $0.setNeedsLayout() }
        repositionViews()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        repositionViews()
    }

    public func beginEditing() {
        self.textField.becomeFirstResponder()
        self.unselectAllTagViews()

        // If the textField isn't visible, scroll to it.
        if !self.bounds.intersects(self.textField.frame) {
            let p = self.textField.frame.origin
            self.contentOffset = p
        }
    }

    public func endEditing() {
        self.textField.resignFirstResponder()
    }

    public override func reloadInputViews() {
        self.textField.reloadInputViews()
    }

    public func addTag(_ tag: TinodeTag) {
        guard self.onValidateTag?(tag) ?? true else {
            return
        }
        guard !self.tagViews.contains(where: { return $0.displayTag == tag }) else {
            return
        }

        if let baseFont = textField.font, tagFont == nil {
            tagFont = baseFont.withSize(baseFont.pointSize - 2)
        }
        let tagView = TagView(tag: tag, usingFont: tagFont)

        tagView.layoutMargins = self.layoutMargins

        tagView.onDidRequestSelection = { [weak self] tagView in
            self?.selectTagView(tagView)
        }

        tagView.onDidRequestDelete = { [weak self] tagView, replacementText in
            // First, refocus the text field
            self?.textField.becomeFirstResponder()
            if !(replacementText?.isEmpty ?? false) {
                self?.textField.text = replacementText
            }
            // Then remove the view from our data
            if let index = self?.tagViews.firstIndex(of: tagView) {
                self?.removeTagAtIndex(index)
            }
        }

        tagView.onDidInputText = { [weak self] _, text in
            if text == "\n" {
                self?.selectNextTag()
            } else {
                self?.textField.becomeFirstResponder()
                self?.textField.text = text
            }
        }

        self.tagViews.append(tagView)
        addSubview(tagView)

        self.textField.text = ""

        // Clearing text programmatically doesn't call this automatically
        updatePlaceholderTextVisibility()
        repositionViews()
    }

    public func addTags(_ tags: [TinodeTag]) {
        tags.forEach { addTag($0) }
    }

    public func removeTagAtIndex(_ index: Int) {
        guard 0 ... self.tagViews.count - 1 ~= index else { return }

        let tagView = self.tagViews[index]
        tagView.removeFromSuperview()
        self.tagViews.remove(at: index)

        updatePlaceholderTextVisibility()
        repositionViews()
    }

    @discardableResult
    public func tokenizeTextFieldText() -> TinodeTag? {
        let text = self.textField.text?.trimmingCharacters(in: CharacterSet.whitespaces) ?? ""
        if !text.isEmpty && (onVerifyTag?(self, text) ?? true) {
            let tag = text as TinodeTag
            addTag(tag)
            self.textField.text = ""
            return tag
        }
        return nil
    }

    // MARK: - Actions
    public func selectNextTag() {
        guard let selectedIndex = tagViews.firstIndex(where: { $0.selected }) else {
            return
        }

        let nextIndex = tagViews.index(after: selectedIndex)
        if nextIndex < tagViews.count {
            tagViews[selectedIndex].selected = false
            tagViews[nextIndex].selected = true
        }
    }

    public func selectTagView(_ tagView: TagView) {
        if tagView.selected {
            tagView.onDidRequestDelete?(tagView, nil)
            return
        }

        tagView.selected = true
        tagViews.filter { $0 != tagView }.forEach {
            $0.selected = false
        }
    }

    public func unselectAllTagViews() {
        tagViews.forEach {
            $0.selected = false
        }
    }

    // Reposition tag views when bounds changes.
    fileprivate var layerBoundsObserver: NSKeyValueObservation?
}

// MARK: Private functions

extension TagsEditView {
    fileprivate func internalInit() {
        self.isScrollEnabled = false
        self.showsHorizontalScrollIndicator = false

        self.layoutMargins = Constants.kTagEditViewMarginLayouts
        self.contentInset = Constants.kTagEditViewContentInsets

        clipsToBounds = true

        textField.backgroundColor = .clear
        textField.autocorrectionType = UITextAutocorrectionType.no
        textField.autocapitalizationType = UITextAutocapitalizationType.none
        textField.spellCheckingType = .no
        textField.delegate = self
        addSubview(textField)

        layerBoundsObserver = self.observe(\.layer.bounds, options: [.old, .new]) { [weak self] _, change in
            guard change.oldValue?.size.width != change.newValue?.size.width else {
                return
            }
            self?.repositionViews()
        }
        textField.onDeleteBackwards = { [weak self] in
            if self?.textField.text?.isEmpty ?? true, let tagView = self?.tagViews.last {
                self?.selectTagView(tagView)
                self?.textField.resignFirstResponder()
            }
        }

        updatePlaceholderTextVisibility()
        repositionViews()

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGestureRecognizer))
        addGestureRecognizer(tapRecognizer)
    }

    @objc func handleTapGestureRecognizer(_ sender: UITapGestureRecognizer) {
        beginEditing()
    }

    fileprivate func calculateContentHeight(layoutWidth: CGFloat) -> CGFloat {
        var totalRect: CGRect = .null
        enumerateItemRects(layoutWidth: layoutWidth) { (_, tagRect: CGRect?, textFieldRect: CGRect?) in
            if let tagRect = tagRect {
                totalRect = tagRect.union(totalRect)
            } else if let textFieldRect = textFieldRect {
                totalRect = textFieldRect.union(totalRect)
            }
        }
        return totalRect.height
    }

    fileprivate func enumerateItemRects(layoutWidth: CGFloat, using closure: (_ tagView: TagView?, _ tagRect: CGRect?, _ textFieldRect: CGRect?) -> Void) {
        if layoutWidth == 0 {
            return
        }

        let maxWidth: CGFloat = layoutWidth - contentInset.left - contentInset.right
        var curX: CGFloat = 0.0
        var curY: CGFloat = 0.0
        var totalHeight: CGFloat = Constants.kTagEditViewStandardRowHeight

        // Tag views Rects
        var tagRect = CGRect.null
        for tagView in tagViews {
            tagRect = CGRect(origin: CGPoint.zero, size: tagView.sizeToFit(.init(width: maxWidth, height: 0)))

            if curX + tagRect.width > maxWidth {
                // Need a new line
                curX = 0
                curY += Constants.kTagEditViewStandardRowHeight + Constants.kTagEditViewSpaceBetweenLines
                totalHeight += Constants.kTagEditViewStandardRowHeight
            }

            tagRect.origin.x = curX
            // Center tagView vertically within kTagEditViewStandardRowHeight
            tagRect.origin.y = curY + ((Constants.kTagEditViewStandardRowHeight - tagRect.height)/2.0)

            closure(tagView, tagRect, nil)

            curX = tagRect.maxX + Constants.kTagEditViewSpaceBetweenTags
        }

        // Always indent TextField by a little bit
        curX += max(0, Constants.kTagEditViewTextfieldHSpace - Constants.kTagEditViewSpaceBetweenTags)
        var availableWidthForTextField: CGFloat = maxWidth - curX

        var textFieldRect = CGRect.zero
        textFieldRect.size.height = Constants.kTagEditViewStandardRowHeight

        if availableWidthForTextField < Constants.kTagEditViewMinTextfieldWidth {
            curX = 0 + Constants.kTagEditViewTextfieldHSpace
            curY += Constants.kTagEditViewStandardRowHeight + Constants.kTagEditViewSpaceBetweenLines
            totalHeight += Constants.kTagEditViewStandardRowHeight
            // Adjust the width
            availableWidthForTextField = maxWidth - curX
        }
        textFieldRect.origin.y = curY
        textFieldRect.origin.x = curX
        textFieldRect.size.width = availableWidthForTextField

        closure(nil, nil, textFieldRect)
    }

    fileprivate func repositionViews() {
        guard self.bounds.width > 0 else {
            return
        }

        var contentRect: CGRect = .null
        enumerateItemRects(layoutWidth: self.bounds.width) { (tagView: TagView?, tagRect: CGRect?, textFieldRect: CGRect?) in
            if let tagRect = tagRect, let tagView = tagView {
                tagView.frame = tagRect
                tagView.setNeedsLayout()
                contentRect = tagRect.union(contentRect)
            } else if let textFieldRect = textFieldRect {
                textField.frame = textFieldRect
                contentRect = textFieldRect.union(contentRect)
            }
        }

        invalidateIntrinsicContentSize()
        let newIntrinsicContentHeight = intrinsicContentSize.height

        if constraints.isEmpty {
            frame.size.height = newIntrinsicContentHeight.rounded()
        }

        self.isScrollEnabled = contentRect.height + contentInset.top + contentInset.bottom >= newIntrinsicContentHeight
        self.contentSize.width = self.bounds.width - contentInset.left - contentInset.right
        self.contentSize.height = contentRect.height

        if self.isScrollEnabled {
            // FIXME: this isn't working. Need to think in a workaround.
            // self.scrollRectToVisible(textField.frame, animated: false)
        }
    }

    fileprivate func updatePlaceholderTextVisibility() {
        textField.placeholder = tagViews.isEmpty ? self.placeholder : nil
    }

    private var maxHeightBasedOnNumberOfLines: CGFloat {
        guard self.numberOfLines > 0 else {
            return CGFloat.infinity
        }
        return contentInset.top + contentInset.bottom + Constants.kTagEditViewStandardRowHeight * CGFloat(numberOfLines) + Constants.kTagEditViewSpaceBetweenLines * CGFloat(numberOfLines - 1)
    }
}

extension TagsEditView: UITextFieldDelegate {
    public func textFieldDidBeginEditing(_ textField: UITextField) {
        unselectAllTagViews()
    }

    public func textFieldDidEndEditing(_ textField: UITextField) {
        if onShouldAcceptTag?(self) ?? true {
            tokenizeTextFieldText()
        }
    }

    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string == "," && onShouldAcceptTag?(self) ?? true {
            tokenizeTextFieldText()
            return false
        }
        return true
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if onShouldAcceptTag?(self) ?? true {
            tokenizeTextFieldText()
        }
        return true
    }
}

extension TagsEditView {
    public var tags: [TinodeTag] {
        get {
            return self.tagViews.map { $0.displayTag }
        }
    }
}
