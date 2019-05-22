//
//  UiUtils.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
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
    static let kMinTagLength = 4
    static let kAvatarSize = 128
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
        return me!.subscribe(set: nil, get: get)
    }
    public static func attachToFndTopic(fndListener: DefaultFndTopic.Listener?) -> PromisedReply<ServerMessage>? {
        let tinode = Cache.getTinode()
        let fnd = tinode.getOrCreateFndTopic()
        fnd.listener = fndListener
        //if fnd.
        return !fnd.attached ?
            fnd.subscribe(set: nil, get: nil) :
            PromisedReply<ServerMessage>(value: ServerMessage())
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

    public static func bytesToHumanSize(_ bytes: Int64) -> String {
        guard bytes > 0 else {
            return "0 Bytes";
        }

        // Not that GB+ are likely to be used ever, just making sure sizes[bucket] does not crash on large values.
        let sizes = ["Bytes", "KB", "MB", "GB", "TB", "PB", "EB"]
        let bucket = (63 - bytes.leadingZeroBitCount) / 10
        let count: Double = Double(bytes) / Double(pow(1024, Double(bucket)))
        // Multiplier for rounding fractions.
        let roundTo: Int = bucket > 0 ? (count < 3 ? 2 : (count < 30 ? 1 : 0)) : 0
        let multiplier: Double = pow(10, Double(roundTo))
        let whole: Int = Int(count)
        let fraction: String = roundTo > 1 ? "." + "\(round(count * multiplier))".suffix(roundTo) : ""
        return "\(whole)\(fraction) \(sizes[bucket])"
    }
}

extension UIViewController {
    // Displays bottom pannel with an error message.
    func showToast(message: String, duration: TimeInterval = 3.0) {
        let iconSize: CGFloat = 32
        let spacing: CGFloat = 8
        let messageHeight = iconSize + spacing * 2
        let toastHeight = max(min(self.view.frame.height * 0.1, 100), messageHeight)

        // Prevent very short toasts
        guard duration > 0.5 else { return }
        let label = UILabel()
        label.textColor = UIColor.white
        label.textAlignment = .left
        label.font = UIFont.preferredFont(forTextStyle: .callout)
        label.text = message
        label.alpha = 1.0
        label.sizeToFit()

        let icon = UIImageView(image: UIImage(named: "outline_error_outline_white_48pt"))
        icon.tintColor = UIColor.white
        icon.frame = CGRect(x: spacing, y: spacing, width: iconSize, height: iconSize)

        label.frame = CGRect(
            x: iconSize + spacing * 2, y: (messageHeight - label.frame.height) / 2,
            width: label.frame.width + spacing * 2, height: label.frame.height)

        let toastView = UIView()
        toastView.alpha = 0
        toastView.backgroundColor = UIColor.red.withAlphaComponent(0.6)
        toastView.addSubview(icon)
        toastView.addSubview(label)

        self.view.addSubview(toastView)
        toastView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toastView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 0),
            toastView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: 0),
            toastView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: toastHeight),
            toastView.heightAnchor.constraint(equalToConstant: toastHeight)
            ])

        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: {
            toastView.alpha = 1
            toastView.transform = CGAffineTransform(translationX: 0, y: -toastHeight)
        }, completion: {(isCompleted) in
            UIView.animate(withDuration: 0.2, delay: duration-0.4, options: .curveEaseIn, animations: {
                toastView.alpha = 0
            }, completion: {(isCompleted) in
                toastView.removeFromSuperview()
            })
        })
    }
}

extension UIImage {

    /// Resize image to given dimentions.
    ///
    /// - Parameters:
    ///     - maxWidth: maxumum width of the image
    ///     - maxHeight: maximum height of the image
    ///     - clip: first crops the image to the new aspect ratio then shrinks it; otherwise the
    ///       image keeps the original aspect ratio but is shrunk to be under the
    ///       maxWidth/maxHeight
    public func resize(width: CGFloat, height: CGFloat, clip: Bool) -> UIImage? {
        let size = sizeUnder(maxWidth: width, maxHeight: height, clip: clip)

        // cropRect for cropping the original image to the required aspect ratio.
        let cropRect = size.src
        let scaleDown = CGAffineTransform(scaleX: size.dst.width / size.src.width, y: size.dst.width / size.src.width)

        // Scale image to the requested dimentions
        guard let imageOut = CIImage(image: self)?.cropped(to: cropRect).transformed(by: scaleDown) else { return nil }

        // This 'UIGraphicsBeginImageContext' is some iOS weirdness. The image cannot be converted to png without it.
        UIGraphicsBeginImageContext(imageOut.extent.size)
        defer { UIGraphicsEndImageContext() }
        UIImage(ciImage: imageOut).draw(in: CGRect(origin: .zero, size: imageOut.extent.size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// Calculate linear dimensions for scaling image down to fit under a certain size.
    /// Returns a tuple which contains destination image sizes, source sizes, and offsets
    /// into source (when 'clip' is true).
    ///
    /// - Parameters:
    ///     - maxWidth: maximum width of the image
    ///     - maxHeight: maximum height of the image
    ///     - clip: first crops the image to the new aspect ratio then shrinks it; otherwise the
    ///       image keeps the original aspect ratio but is shrunk to be under the
    ///       maxWidth/maxHeight
    public func sizeUnder(maxWidth: CGFloat, maxHeight: CGFloat, clip: Bool) -> (dst: CGSize, src: CGRect) {

        // Sanity check
        assert(maxWidth > 0 && maxHeight > 0, "Maxumum dimensions must be positive")

        let originalWidth = CGFloat(self.size.width)
        let originalHeight = CGFloat(self.size.height)

        // scale is [0,1): 0 - very large original, 1: under the limits already.
        let scaleX = min(originalWidth, maxWidth) / originalWidth
        let scaleY = min(originalHeight, maxHeight) / originalHeight
        let scale = clip ?
            // How much to scale the image with at least of of either width or height below the limits; clip the other dimension, the image will have the new aspect ratio.
            max(scaleX, scaleY) :
            // How much to scale the image that has both width and height below the limits: no clipping will occur,
            // the image will keep the original aspect ratio.
            min(scaleX, scaleY)

        let dstSize = CGSize(width: min(maxWidth, originalWidth * scale), height: min(maxHeight, originalHeight * scale))

        let srcWidth = dstSize.width / scale
        let srcHeight = dstSize.height / scale

        return (
            dst: dstSize,
            src: CGRect(
                x: 0.5 * (originalWidth - srcWidth),
                y: 0.5 * (originalHeight - srcHeight),
                width: srcWidth,
                height: srcHeight
            )
        )
    }
}

class RelativeDateFormatter {
    // DateFormatter is thread safe, OK to keep a copy.
    static let shared = RelativeDateFormatter()

    private let formatter = DateFormatter()

    func dateOnly(from date: Date?, style: DateFormatter.Style = .medium) -> String {
        guard let date = date else { return "Never ??:??" }

        formatter.timeStyle = .none
        formatter.dateStyle = style
        switch true {
        case Calendar.current.isDateInToday(date) || Calendar.current.isDateInYesterday(date):
            // "today", "yesterday"
            formatter.doesRelativeDateFormatting = true
        case Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear):
            // day of the week "Wednesday", "Friday" etc
            formatter.dateFormat = "EEEE"
        default:
            // All other dates: "Mar 15, 2019"
            break
        }
        return formatter.string(from: date)
    }

    func timeOnly(from date: Date?, style: DateFormatter.Style = .short) -> String {
        guard let date = date else { return "??:??" }

        formatter.timeStyle = style
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
