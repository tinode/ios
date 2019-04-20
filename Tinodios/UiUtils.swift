//
//  UiUtils.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import MessageKit
import TinodeSDK

class UiTinodeEventListener : TinodeEventListener {
    // TODO: implement online/offline indicator changes.
    private var connected: Bool = false

    init(connected: Bool) {
        self.connected = connected
    }
    func onConnect(code: Int, reason: String, params: [String : JSONValue]?) {
        connected = true
    }
    func onDisconnect(byServer: Bool, code: Int, reason: String) {
        connected = false
    }
    func onLogin(code: Int, text: String) {}
    func onMessage(msg: ServerMessage?) {}
    func onRawMessage(msg: String) {}
    func onCtrlMessage(ctrl: MsgServerCtrl?) {}
    func onDataMessage(data: MsgServerData?) {}
    func onInfoMessage(info: MsgServerInfo?) {}
    func onMetaMessage(meta: MsgServerMeta?) {}
    func onPresMessage(pres: MsgServerPres?) {}
}

class UiUtils {
    public static func attachToMeTopic(meListener: DefaultMeTopic.Listener?) -> PromisedReply<ServerMessage>? {
        let tinode = Cache.getTinode()
        var me = tinode.getMeTopic()
        if me == nil  {
            me = DefaultMeTopic(tinode: tinode, l: meListener)
        } else {
            me!.listener = meListener
        }
        let get = me!.getMetaGetBuilder().withGetDesc().withGetSub().build()
        // TODO: logout on failure and route to login view.
        do {
            return try me!.subscribe(set: nil, get: get)
        } catch {
            print("failed in ME.subscribe: \(error)")
            return nil
        }
    }

    // Get text from UITextField or mark the field red if the field is blank
    public static func ensureDataInTextField(_ field: UITextField) -> String {
        let text = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            markTextFieldAsError(field)
            return ""
        }
        return text
    }
    public static func markTextFieldAsError(_ field: UITextField) {
        // Make border red to signify error.
        field.layer.borderColor = UIColor.red.cgColor
        field.layer.borderWidth = 1.0
    }
    public static func clearTextFieldError(_ field: UITextField) {
        // Reset red border to default.
        field.layer.borderWidth = 0.0
    }
}

extension UIViewController {
    // Displays Android-style toast
    func showToast(message: String, duration: TimeInterval = 3.0) {
        // Prevent very short toasts
        guard duration > 0.5 else { return }

        let toastLabel = UILabel()
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        toastLabel.textColor = UIColor.white
        toastLabel.textAlignment = .center;
        toastLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        toastLabel.text = message
        toastLabel.alpha = 1.0
        toastLabel.layer.cornerRadius = 10;
        toastLabel.clipsToBounds  =  true
        toastLabel.sizeToFit()
        toastLabel.frame = CGRect(
            x: self.view.frame.size.width/2 - toastLabel.frame.width / 2 - 8,
            y: self.view.frame.size.height - 100, width: toastLabel.frame.width + 16, height: 35
        )
        self.view.addSubview(toastLabel)
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: {
            toastLabel.alpha = 1
        }, completion: {(isCompleted) in
            UIView.animate(withDuration: 0.2, delay: duration-0.4, options: .curveEaseIn, animations: {
                toastLabel.alpha = 0
            }, completion: {(isCompleted) in
                toastLabel.removeFromSuperview()
            })
        })
    }
}

extension UIImage {

    // Resize image to given dimentions. If 'clip' is true and aspect ratios are different, crop the central
    // part of the source image and scale it down to the given dimentions.
    public func resize(width: Float, height: Float, clip: Bool) -> UIImage? {
        guard let size = calcSize(maxWidth: width, maxHeight: height, clip: clip) else { return nil }

        // cropRect for cropping the original image to the required aspect ratio.
        let cropRect = CGRect(x: size.xOffset, y: size.yOffset, width: Int(size.srcWidth), height: Int(size.srcHeight))
        let scaleDown = CGAffineTransform(scaleX: CGFloat(size.dstWidth / size.srcWidth),
                                          y: CGFloat(size.dstWidth / size.srcWidth))

        // Scale image to the requested dimentions
        guard let imageOut = CIImage(image: self)?.cropped(to: cropRect).transformed(by: scaleDown) else { return nil }

        // This is some iOS weirdness. The image cannot be converted to png without it.
        UIGraphicsBeginImageContext(imageOut.extent.size)
        defer { UIGraphicsEndImageContext() }
        UIImage(ciImage: imageOut).draw(in: CGRect(origin: .zero, size: imageOut.extent.size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // Calculate linear dimensions for scaling image down to fit under a certain size.
    // Returns a tuple which contains destination image sizes, source sizes, and offsets
    // into source (when 'clip' is true).
    //
    // The 'clip' parameter forces image to have the new dimensions. Otherwise the
    // image keeps the original aspect ratio with width and hight being under the
    // maxWindth/maxHeight
    private func calcSize(maxWidth: Float, maxHeight: Float, clip: Bool) -> (dstWidth: Float, dstHeight: Float, xOffset: Int, yOffset: Int, srcWidth: Float, srcHeight: Float)? {

        // Sanity check
        guard maxWidth > 0 && maxHeight > 0 else { return nil }

        let originalWidth = Float(self.size.width)
        let originalHeight = Float(self.size.height)

        let scaleX = min(originalWidth, maxWidth) / originalWidth
        let scaleY = min(originalHeight, maxHeight) / originalHeight
        let scale = clip ?
            // How much to scale the image that eidth width or height are below the limits; clip the other dimension,
            // the image will have the new aspect ratio.
            max(scaleX, scaleY) :
            // How much to scale the image that both width and height are below the limits: no clipping will occur,
            // the image will keep the original aspect ratio.
            min(scaleX, scaleY)

        let dstWidth = min(maxWidth, originalWidth * scale)
        let dstHeight = min(maxHeight, originalHeight * scale)

        let srcWidth = dstWidth / scale
        let srcHeight = dstHeight / scale

        return (
            dstWidth: dstWidth,
            dstHeight: dstHeight,
            xOffset: Int(0.5 * (originalWidth - srcWidth)),
            yOffset: Int(0.5 * (originalHeight - srcHeight)),
            srcWidth: srcWidth,
            srcHeight: srcHeight
        )
    }
}

extension Date {

    // Date formatter for message timestamps. Length of string is dependent on difference from current time.
    public func formatRelative() -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        let now = Date()
        if calendar.component(.year, from: self) == calendar.component(.year, from: now) {
            // Same year, no need to show the year.

            if calendar.component(.month, from: self) == calendar.component(.month, from: now) &&
                calendar.component(.day, from: self) == calendar.component(.day, from: now) {
                // The difference is only in time.
                formatter.dateStyle = .none
                formatter.timeStyle = .short
            } else {
                // Different dates same year
                formatter.dateStyle = .short
                formatter.timeStyle = .short
            }
        } else {
            // Different year, show all.
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        }

        return formatter.string(from: self)
    }
}

extension AvatarView {

    public convenience init(icon: UIImage?, title: String?, id: String?) {
        self.init()
        self.set(icon: icon, title: title, id: id)
    }

    override open var bounds: CGRect {
        didSet {
            // Repeating the call from super.didSet because design of AvatarView isn't great + swift is bad.
            setCorner(radius: nil)
            if let initials = initials {
                // Force redrawing the placeholder image when size changes
                self.initials = "" + initials
            }
        }
    }

    public func set(icon: UIImage?, title: String?, id: String?) {
        if let icon = icon {
            self.set(avatar: Avatar(image: icon))
        } else {
            self.adjustsFontSizeToFitWidth = false
            self.placeholderFont = UIFont.preferredFont(forTextStyle: .title2)
            let (fg, bg) = AvatarView.selectBackground(id: id, dark: Tinode.topicTypeByName(name: id) == TopicType.p2p)
            self.placeholderTextColor = fg
            self.backgroundColor = bg

            // Avatar placeholder.
            var firstChar = title ?? ""
            firstChar = firstChar.isEmpty ? "?" : firstChar
            self.set(avatar: Avatar(initials: String(firstChar[firstChar.startIndex]).uppercased()))
        }
    }

    static func selectBackground(id: String?, dark: Bool = false) -> (UIColor, UIColor) {
        guard let id = id else {
            return (UIColor.white, UIColor.gray)
        }

        let defaultBackgroundColorLight = UIColor(red: 0x9e/255, green: 0x9e/255, blue: 0x9e/255, alpha: 1.0)
        let defaultBackgroundColorDark = UIColor(red: 0x75/255, green: 0x75/255, blue: 0x75/255, alpha: 1.0)
        let foregroundColorDark = UIColor(red: 0xDE/255, green: 0xDE/255, blue: 0xDE/255, alpha: 1.0)
        let foregroundColorLight = UIColor.white

        let lightColors: [UIColor] = [
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
        let darkColors: [UIColor] = [
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

        let hash = UInt(id.hashCode().magnitude)
        if hash == 0 {
            return dark ?
                (foregroundColorDark, defaultBackgroundColorDark) :
                (foregroundColorLight, defaultBackgroundColorLight)
        } else if dark {
            return (foregroundColorDark, darkColors[Int(hash % UInt(darkColors.count))])
        } else {
            return (foregroundColorLight, lightColors[Int(hash % UInt(lightColors.count))])
        }
    }
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
