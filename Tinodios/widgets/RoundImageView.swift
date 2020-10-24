//
//  RoundImageView.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

// Implementation of a circular image view with either an image or letters

import TinodeSDK
import UIKit

@IBDesignable class RoundImageView: UIImageView {

    public enum IconType {
        case p2p, grp, none

        init(from: String) {
            switch from {
            case "p2p": self = .p2p
            case "grp": self = .grp
            default: self = .none
            }
        }
    }

    // MARK: - Properties
    public var iconType: IconType = .none {
        didSet {
            updateDefaultIcon()
        }
    }

    /// Element to set default icon type when no other info is provided: "grp" or "p2p".
    @IBInspectable public var defaultType: String? {
        didSet {
            guard let tp = defaultType else { return }
            iconType = IconType(from: tp)
        }
    }

    public var initials: String? {
        didSet {
            setImageFrom(initials: initials)
        }
    }

    public var letterTileFont: UIFont = UIFont.preferredFont(forTextStyle: .caption1) {
        didSet {
            setImageFrom(initials: initials)
        }
    }

    public var letterTileTextColor: UIColor = .white {
        didSet {
            setImageFrom(initials: initials)
        }
    }

    private var radius: CGFloat?

    // MARK: - Overridden Properties
    override var frame: CGRect {
        didSet {
            setCornerRadius()
        }
    }

    override var bounds: CGRect {
        didSet {
            setCornerRadius()
            if let initials = initials {
                // Rescale letters on size changes.
                image = getImageFrom(initials: initials)
            }
        }
    }

    // MARK: - Initializers

    override public init(frame: CGRect) {
        super.init(frame: frame)
        prepareView()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        prepareView()
    }

    convenience public init() {
        self.init(frame: .zero)
    }

    convenience public init(icon: UIImage?, title: String?, id: String?) {
        self.init(frame: .zero)
        self.set(icon: icon, title: title, id: id)
    }

    public func set(icon: UIImage?, title: String?, id: String?) {
        if let icon = icon {
            // Avatar image provided.
            self.image = icon
            // Clear background color.
            self.backgroundColor = nil
        } else {
            if let id = id, !id.isEmpty {
                switch Tinode.topicTypeByName(name: id) {
                case .p2p: iconType = .p2p
                case .grp: iconType = .grp
                default: break
                }
            }

            if let title = title, !title.isEmpty {
                // No avatar image but have avatar name, show initial.
                self.letterTileFont = UIFont.preferredFont(forTextStyle: .title2)
                let (fg, bg) = RoundImageView.selectBackground(id: id, dark: iconType == .p2p)
                self.letterTileTextColor = fg
                self.backgroundColor = bg

                self.initials = String(title[title.startIndex]).uppercased()
            } else {
                // Placeholder image
                updateDefaultIcon()
                self.backgroundColor = nil
            }
        }
    }

    public func setIconType(_ type: IconType) {
        self.iconType = type
    }

    private static func selectBackground(id: String?, dark: Bool = false) -> (UIColor, UIColor) {
        guard let id = id else {
            return (UIColor.white, UIColor.gray)
        }

        let defaultBackgroundColorLight = UIColor(red: 0x9e/255, green: 0x9e/255, blue: 0x9e/255, alpha: 1.0)
        let defaultBackgroundColorDark = UIColor(red: 0x75/255, green: 0x75/255, blue: 0x75/255, alpha: 1.0)
        let foregroundColorDark = UIColor(red: 0xDE/255, green: 0xDE/255, blue: 0xDE/255, alpha: 1.0)
        let foregroundColorLight = UIColor.white

        let hash = UInt(id.hashCode().magnitude)
        if hash == 0 {
            return dark ?
                (foregroundColorDark, defaultBackgroundColorDark) :
                (foregroundColorLight, defaultBackgroundColorLight)
        } else if dark {
            return (foregroundColorDark, kDarkColors[Int(hash % UInt(kDarkColors.count))])
        } else {
            return (foregroundColorLight, kLightColors[Int(hash % UInt(kLightColors.count))])
        }
    }

    private func setImageFrom(initials: String?) {
        guard let initials = initials else { return }
        image = getImageFrom(initials: initials)
    }

    private func getImageFrom(initials: String) -> UIImage {
        let width = frame.width
        let height = frame.height
        if width == 0 || height == 0 { return UIImage() }
        var font = letterTileFont

        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), false, UIScreen.main.scale)
        defer { UIGraphicsEndImageContext() }
        let context = UIGraphicsGetCurrentContext()!


        let textRect = calcTextRect(outerViewWidth: width)
        // Maybe adjust font size to make sure the text fits inside the circle.
        font = adjustFontSize(text: initials, font: font, width: textRect.width, height: textRect.height)

        let textStyle = NSMutableParagraphStyle()
        textStyle.alignment = .center
        let textFontAttributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key.font: font, NSAttributedString.Key.foregroundColor: letterTileTextColor, NSAttributedString.Key.paragraphStyle: textStyle]

        let textTextHeight: CGFloat = initials.boundingRect(with: CGSize(width: textRect.width, height: CGFloat.infinity), options: .usesLineFragmentOrigin, attributes: textFontAttributes, context: nil).height
        context.saveGState()
        context.clip(to: textRect)
        initials.draw(in: CGRect(x: textRect.minX, y: textRect.minY + (textRect.height - textTextHeight) / 2, width: textRect.width, height: textTextHeight), withAttributes: textFontAttributes)
        context.restoreGState()

        guard let renderedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            assertionFailure("Could not create image from context")
            return UIImage()
        }
        return renderedImage
    }

    // Find the biggest font to fit the text with the given width and height.
    // If no adjustment is needed, returns the original font.
    private func adjustFontSize(text: String, font: UIFont, width: CGFloat, height: CGFloat) -> UIFont {
        var attributedText = NSAttributedString(string: text, attributes: [.font: font])
        var newFont = font
        while attributedText.width(considering: height) > width {
            newFont = font.withSize(newFont.pointSize / 1.25)
            attributedText = NSAttributedString(string: text, attributes: [.font: newFont])
        }
        return newFont
    }

    // Calculate the size of the square which fits inside the cirlce of the given diameter.
    private func calcTextRect(outerViewWidth diameter: CGFloat) -> CGRect {
        let size = diameter * 0.70710678118 // = sqrt(2) / 2
        let offset = diameter * 0.1464466094 // (1 - sqrt(2) / 2) / 2
        // In case the font exactly fits to the region, put 2 pixels both left and right
        return CGRect(x: offset+2, y: offset, width: size-4, height: size)
    }

    private func prepareView() {
        backgroundColor = .gray
        contentMode = .scaleAspectFill
        layer.masksToBounds = true
        clipsToBounds = true
        setCornerRadius()
        updateDefaultIcon()
    }

    private func updateDefaultIcon() {
        let icon: UIImage?
        switch iconType {
        case .p2p: icon = UIImage(named: "user-96")
        case .grp: icon = UIImage(named: "group-96")
        default: icon =  nil
        }
        self.image = icon
    }

    private func setCornerRadius() {
        layer.cornerRadius = min(frame.width, frame.height)/2
    }

    private static let kLightColors: [UIColor] = [
        UIColor(red: 0xef/255, green: 0x9a/255, blue: 0x9a/255, alpha: 1.0),
        UIColor(red: 0x90/255, green: 0xca/255, blue: 0xf9/255, alpha: 1.0),
        UIColor(red: 0xb0/255, green: 0xbe/255, blue: 0xc5/255, alpha: 1.0),
        UIColor(red: 0xb3/255, green: 0x9d/255, blue: 0xdb/255, alpha: 1.0),
        UIColor(red: 0xff/255, green: 0xab/255, blue: 0x91/255, alpha: 1.0),
        UIColor(red: 0xa5/255, green: 0xd6/255, blue: 0xa7/255, alpha: 1.0),
        UIColor(red: 0xdd/255, green: 0xdd/255, blue: 0xdd/255, alpha: 1.0),
        UIColor(red: 0xe6/255, green: 0xee/255, blue: 0x9c/255, alpha: 1.0),
        UIColor(red: 0xc5/255, green: 0xe1/255, blue: 0xa5/255, alpha: 1.0),
        UIColor(red: 0xff/255, green: 0xf5/255, blue: 0x9d/255, alpha: 1.0),
        UIColor(red: 0xf4/255, green: 0x8f/255, blue: 0xb1/255, alpha: 1.0),
        UIColor(red: 0x9f/255, green: 0xa8/255, blue: 0xda/255, alpha: 1.0),
        UIColor(red: 0xff/255, green: 0xe0/255, blue: 0x82/255, alpha: 1.0),
        UIColor(red: 0xbc/255, green: 0xaa/255, blue: 0xa4/255, alpha: 1.0),
        UIColor(red: 0x80/255, green: 0xde/255, blue: 0xea/255, alpha: 1.0),
        UIColor(red: 0xce/255, green: 0x93/255, blue: 0xd8/255, alpha: 1.0)
    ]

    private static let kDarkColors: [UIColor] = [
        UIColor(red: 0xC6/255, green: 0x28/255, blue: 0x28/255, alpha: 1.0),
        UIColor(red: 0xAD/255, green: 0x14/255, blue: 0x57/255, alpha: 1.0),
        UIColor(red: 0x6A/255, green: 0x1B/255, blue: 0x9A/255, alpha: 1.0),
        UIColor(red: 0x45/255, green: 0x27/255, blue: 0xA0/255, alpha: 1.0),
        UIColor(red: 0x28/255, green: 0x35/255, blue: 0x93/255, alpha: 1.0),
        UIColor(red: 0x15/255, green: 0x65/255, blue: 0xC0/255, alpha: 1.0),
        UIColor(red: 0x02/255, green: 0x77/255, blue: 0xBD/255, alpha: 1.0),
        UIColor(red: 0x00/255, green: 0x83/255, blue: 0x8F/255, alpha: 1.0),
        UIColor(red: 0x00/255, green: 0x69/255, blue: 0x5C/255, alpha: 1.0),
        UIColor(red: 0x2E/255, green: 0x7D/255, blue: 0x32/255, alpha: 1.0),
        UIColor(red: 0x55/255, green: 0x8B/255, blue: 0x2F/255, alpha: 1.0),
        UIColor(red: 0x9E/255, green: 0x9D/255, blue: 0x24/255, alpha: 1.0),
        UIColor(red: 0xF9/255, green: 0xA8/255, blue: 0x25/255, alpha: 1.0),
        UIColor(red: 0xFF/255, green: 0x8F/255, blue: 0x00/255, alpha: 1.0),
        UIColor(red: 0xEF/255, green: 0x6C/255, blue: 0x00/255, alpha: 1.0),
        UIColor(red: 0xD8/255, green: 0x43/255, blue: 0x15/255, alpha: 1.0)
    ]
}

// These extensions are needed for selecting the color of avatar background
fileprivate extension Character {
    var asciiValue: UInt32? {
        return String(self).unicodeScalars.filter{$0.isASCII}.first?.value
    }
}

fileprivate extension String {
    // ASCII array to map the string
    var asciiArray: [UInt32] {
        return unicodeScalars.filter{$0.isASCII}.map{$0.value}
    }

    // hashCode produces output equal to the Java hash function.
    func hashCode() -> Int32 {
        var hash : Int32 = 0
        for i in self.asciiArray {
            hash = 31 &* hash &+ Int32(i) // Be aware of overflow operators,
        }
        return hash
    }
}

extension NSAttributedString {
    internal func width(considering height: CGFloat) -> CGFloat {
        let constraintBox = CGSize(width: .greatestFiniteMagnitude, height: height)
        let rect = self.boundingRect(with: constraintBox, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return rect.width
    }
}
