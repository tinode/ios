//
//  UiUtils.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

class UiTinodeEventListener : TinodeEventListener {
    private var connected: Bool = false

    init(connected: Bool) {
        self.connected = connected
    }
    func onConnect(code: Int, reason: String, params: [String : JSONValue]?) {
        connected = true
    }
    func onDisconnect(byServer: Bool, code: Int, reason: String) {
        if connected {
            // If we just got disconnected, display the connection lost message.
            DispatchQueue.main.async {
                UiUtils.showToast(message: "Connection to server lost.")
            }
        }
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

enum ToastLevel {
    case error, warning, info
}

class UiUtils {
    static let kMinTagLength = 4
    static let kAvatarSize: CGFloat = 128
    static let kMaxBitmapSize: CGFloat = 1024

    public static func attachToMeTopic(meListener: DefaultMeTopic.Listener?) -> PromisedReply<ServerMessage>? {
        let tinode = Cache.getTinode()
        var me = tinode.getMeTopic()
        if me == nil  {
            me = DefaultMeTopic(tinode: tinode, l: meListener)
        } else {
            me!.listener = meListener
        }
        let get = me!.getMetaGetBuilder().withDesc().withSub().build()
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

    public static func routeToLoginVC() {
        DispatchQueue.main.async {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let destinationVC = storyboard.instantiateViewController(withIdentifier: "StartNavigator") as! UINavigationController

            if let window = UIApplication.shared.keyWindow {
                window.rootViewController = destinationVC
            }
        }
    }

    public static func routeToChatListVC() {
        DispatchQueue.main.async {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let initialViewController =
                storyboard.instantiateViewController(
                    withIdentifier: "ChatsNavigator") as! UINavigationController
            if let window = UIApplication.shared.keyWindow {
                window.rootViewController = initialViewController
            }
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

    public static func bytesToHumanSize(_ bytes: Int64) -> String {
        guard bytes > 0 else {
            return "0 Bytes"
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

    /// Displays bottom pannel with an error message.
    /// - Parameters:
    ///  - message: message to display
    ///  - duration: duration of display in seconds.
    public static func showToast(message: String, duration: TimeInterval = 3.0, level: ToastLevel = .error) {
        guard let parent = UIApplication.shared.windows.last else { return }

        let iconSize: CGFloat = 32
        let spacing: CGFloat = 8
        let minMessageHeight = iconSize + spacing * 2
        let maxMessageHeight: CGFloat = 100

        // Prevent very short toasts
        guard duration > 0.5 else { return }

        var settings: (color: UInt, bgColor: UInt, icon: String)
        switch level {
        case .error: settings = (color: 0xFFFFFFFF, bgColor: 0xFFFF6666, icon: "important-32")
        case .warning: settings = (color: 0xFF666633, bgColor: 0xFFFFFFCC, icon: "warning-32")
        case .info: settings = (color: 0xFF333366, bgColor: 0xFFCCCCFF, icon: "info-32")
        }
        let icon = UIImageView(image: UIImage(named: settings.icon))
        icon.tintColor = UIColor(fromHexCode: settings.color)
        icon.frame = CGRect(x: spacing, y: spacing, width: iconSize, height: iconSize)

        let label = UILabel()
        label.textColor = UIColor(fromHexCode: settings.color)
        label.textAlignment = .left
        label.lineBreakMode = .byWordWrapping
        label.numberOfLines = 3
        label.font = UIFont.preferredFont(forTextStyle: .callout)
        label.text = message
        label.alpha = 1.0
        let maxLabelWidth = parent.frame.width - spacing * 3 - iconSize

        let labelBounds = label.textRect(forBounds: CGRect(x: 0, y: 0, width: maxLabelWidth, height: CGFloat.greatestFiniteMagnitude), limitedToNumberOfLines: label.numberOfLines)
        label.frame = CGRect(
            x: iconSize + spacing * 2, y: spacing + (iconSize - label.font.lineHeight) * 0.5,
            width: labelBounds.width, height: labelBounds.height)

        let toastView = UIView()
        toastView.alpha = 0
        toastView.backgroundColor = UIColor(fromHexCode: settings.bgColor)
        toastView.addSubview(icon)
        toastView.addSubview(label)

        parent.addSubview(toastView)
        label.sizeToFit()

        let toastHeight = max(min(label.frame.height + spacing * 3, maxMessageHeight), minMessageHeight)
        toastView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toastView.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 0),
            toastView.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: 0),
            toastView.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: toastHeight),
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
    public static func setupTapRecognizer(forView view: UIView, action: Selector?, actionTarget: UIViewController) {
        let tap = UITapGestureRecognizer(target: actionTarget, action: action)
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tap)
    }
    public static func dismissKeyboardForTaps(onView view: UIView) {
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }
    public static func ToastFailureHandler(err: Error) throws -> PromisedReply<ServerMessage>? {
        DispatchQueue.main.async {
            if let e = err as? TinodeError, case .notConnected = e {
                UiUtils.showToast(message: "You are offline.")
            } else {
                UiUtils.showToast(message: "Action failed: \(err)")
            }
        }
        return nil
    }
    public static func ToastSuccessHandler(msg: ServerMessage?) throws -> PromisedReply<ServerMessage>? {
        if let ctrl = msg?.ctrl, ctrl.code >= 300 {
            DispatchQueue.main.async {
                UiUtils.showToast(message: "Something went wrong: \(ctrl.code) - \(ctrl.text)", level: .warning)
            }
        }
        return nil
    }
    public static func showPermissionsEditDialog(over viewController: UIViewController?, acs: AcsHelper, callback: PermissionsEditViewController.ChangeHandler?, disabledPermissions: String?) {
        let alertVC = PermissionsEditViewController(set: acs.description, disabled: disabledPermissions, changeHandler: callback)
        alertVC.show(over: viewController)
    }

    public enum PermissionsChangeType {
        case updateSelfSub, updateSub, updateAuth, updateAnon
    }

    @discardableResult
    public static func handlePermissionsChange(onTopic topic: DefaultTopic, forUid uid: String?, changeType: PermissionsChangeType, newPermissions: String)
        -> PromisedReply<ServerMessage>? {
        do {
            var reply: PromisedReply<ServerMessage>? = nil
            switch changeType {
            case .updateSelfSub:
                reply = topic.updateMode(uid: nil, update: newPermissions)
            case .updateSub:
                reply = topic.updateMode(uid: uid, update: newPermissions)
            case .updateAuth:
                reply = topic.updateDefacs(auth: newPermissions, anon: nil)
            case .updateAnon:
                reply = topic.updateDefacs(auth: nil, anon: newPermissions)
            }
            return try reply?.then(
                onSuccess: { msg in
                    if let ctrl = msg?.ctrl, ctrl.code >= 300 {
                        DispatchQueue.main.async {
                            UiUtils.showToast(message: "Permissions not modified: \(ctrl.text) (\(ctrl.code))", level: .warning)
                        }
                    }
                    return nil
                },
                onFailure: { err in
                    DispatchQueue.main.async {
                        UiUtils.showToast(message: "Error changing permissions: \(err.localizedDescription)")
                    }
                    return nil
                })
        } catch {
            print("Error changing permissions \(error)")
            return nil
        }
    }
    @discardableResult
    public static func updateAvatar(forTopic topic: DefaultTopic, image: UIImage) -> PromisedReply<ServerMessage>? {
        let pub = topic.pub == nil ? VCard(fn: nil, avatar: image) : topic.pub!.copy()
        pub.photo = Photo(image: image)
        return UiUtils.setTopicData(forTopic: topic, pub: pub, priv: nil)
    }
    @discardableResult
    public static func setTopicData(
        forTopic topic: DefaultTopic, pub: VCard?, priv: PrivateType?) -> PromisedReply<ServerMessage>? {
        do {
            return try topic.setDescription(pub: pub, priv: priv)?.then(
                onSuccess: UiUtils.ToastSuccessHandler,
                onFailure: UiUtils.ToastFailureHandler)
        } catch {
            UiUtils.showToast(message: "Error changing public data \(error)")
            return nil
        }
    }

    private static func topViewController(rootViewController: UIViewController?) -> UIViewController? {
        guard let rootViewController = rootViewController else { return nil }
        guard let presented = rootViewController.presentedViewController else {
            return rootViewController
        }
        switch presented {
        case let navigationController as UINavigationController:
            return topViewController(rootViewController: navigationController.viewControllers.last)
        case let tabBarController as UITabBarController:
            return topViewController(rootViewController: tabBarController.selectedViewController)
        default:
            return topViewController(rootViewController: presented)
        }
    }

    public static func presentFileSharingVC(for fileUrl: URL) {
        DispatchQueue.main.async {
            let filesToShare = [fileUrl]
            let activityViewController = UIActivityViewController(activityItems: filesToShare, applicationActivities: nil)
            let topVC = UiUtils.topViewController(
                rootViewController: UIApplication.shared.keyWindow?.rootViewController)
            topVC?.present(activityViewController, animated: true, completion: nil)
        }
    }

    public static func toggleProgressOverlay(in parent: UIViewController, visible: Bool, title: String? = nil) {
        if visible {
            let alert = UIAlertController(title: nil, message: title ?? "Please wait...", preferredStyle: .alert)

            let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
            loadingIndicator.hidesWhenStopped = true
            loadingIndicator.style = UIActivityIndicatorView.Style.gray
            loadingIndicator.startAnimating()

            alert.view.addSubview(loadingIndicator)
            parent.present(alert, animated: true, completion: nil)
        } else if let vc = parent.presentedViewController, vc is UIAlertController {
            parent.dismiss(animated: false, completion: nil)
        }
    }
}

extension UIViewController {
    public func presentChatReplacingCurrentVC(with topicName: String, afterDelay delay: DispatchTimeInterval = .seconds(0)) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let navController = self.navigationController {
                navController.popToRootViewController(animated: false)

                let messageVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "MessageViewController") as! MessageViewController
                messageVC.topicName = topicName
                navController.pushViewController(messageVC, animated: true)
            }
        }
    }
}

extension UIImage {
    private static let kScaleFactor: CGFloat = 0.70710678118 // 1.0/SQRT(2)
    public typealias ScalingData = (dst: CGSize, src: CGRect, altered: Bool)

    private static func resizeImage(image: UIImage, newSize size: ScalingData) -> UIImage? {
        // cropRect for cropping the original image to the required aspect ratio.
        let cropRect = size.src
        let scaleDown = CGAffineTransform(scaleX: size.dst.width / size.src.width, y: size.dst.width / size.src.width)

        // Scale image to the requested dimentions
        guard let imageOut = CIImage(image: image)?.cropped(to: cropRect).transformed(by: scaleDown) else { return nil }

        // This 'UIGraphicsBeginImageContext' is some iOS weirdness. The image cannot be converted to png without it.
        UIGraphicsBeginImageContext(imageOut.extent.size)
        defer { UIGraphicsEndImageContext() }
        UIImage(ciImage: imageOut).draw(in: CGRect(origin: .zero, size: imageOut.extent.size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// Resize the image to given physical (i.e. device pixels, not logical pixels) dimentions.
    /// If the image does not need to be changed, return the original.
    ///
    /// - Parameters:
    ///     - maxWidth: maxumum width of the image
    ///     - maxHeight: maximum height of the image
    ///     - clip: first crops the image to the new aspect ratio then shrinks it; otherwise the
    ///       image keeps the original aspect ratio but is shrunk to be under the
    ///       maxWidth/maxHeight
    public func resize(width: CGFloat, height: CGFloat, clip: Bool) -> UIImage? {
        let size = sizeUnder(maxWidth: width, maxHeight: height, clip: clip)

        // Don't mess with image if it does not need to be scaled.
        guard size.altered else { return self }

        return UIImage.resizeImage(image: self, newSize: size)
    }

    /// Resize the image to the given bytesize keeping the original aspect ratio and format, of possible.
    public func resize(byteSize: Int, asMimeType mime: String?) -> UIImage? {
        // Sanity check
        assert(byteSize > 100, "Maxumum byte size must be more than 100 bytes")

        var image: UIImage = self
        guard var bits = image.pixelData(forMimeType: mime) else { return nil }
        while bits.count > byteSize {
            let originalWidth = CGFloat(image.size.width * image.scale)
            let originalHeight = CGFloat(image.size.height * image.scale)

            guard let newImage = UIImage.resizeImage(image: image, newSize: image.sizeUnder(maxWidth: originalWidth * UIImage.kScaleFactor, maxHeight: originalHeight * UIImage.kScaleFactor, clip: false)) else { return nil }
            image = newImage

            guard let newBits = image.pixelData(forMimeType: mime) else { return nil }
            bits = newBits
        }

        return image
    }

    /// Calculate physical (not logical, i.e. UIImage.scale is factored in) linear dimensions
    /// for scaling image down to fit under a certain size.
    ///
    /// - Parameters:
    ///     - maxWidth: maximum width of the image
    ///     - maxHeight: maximum height of the image
    ///     - clip: first crops the image to the new aspect ratio then shrinks it; otherwise the
    ///       image keeps the original aspect ratio but is shrunk to be under the
    ///       maxWidth/maxHeight
    /// - Returns:
    ///     a tuple which contains destination image sizes, source sizes and offsets
    ///     into source (when 'clip' is true), an indicator that the new dimensions are different
    ///     from the original.
    public func sizeUnder(maxWidth: CGFloat, maxHeight: CGFloat, clip: Bool) -> ScalingData {

        // Sanity check
        assert(maxWidth > 0 && maxHeight > 0, "Maxumum dimensions must be positive")

        let originalWidth = CGFloat(self.size.width * self.scale)
        let originalHeight = CGFloat(self.size.height * self.scale)

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
            ),
            altered: originalWidth != dstSize.width || originalHeight != dstSize.height
        )
    }

    public func pixelData(forMimeType mime: String?) -> Data? {
        return mime != "image/png" ? jpegData(compressionQuality: 0.8) : pngData()
    }
}

extension UIColor {
    convenience init(fromHexCode code: UInt) {
        let blue = code & 0xff
        let green = (code >> 8) & 0xff
        let red = (code >> 16) & 0xff
        let alpha = (code >> 24) & 0xff
        self.init(red: CGFloat(Float(red) / 255.0),
                  green: CGFloat(green) / 255.0,
                  blue: CGFloat(blue) / 255.0,
                  alpha: CGFloat(alpha) / 255.0)
    }
}

public enum UIButtonBorderSide {
    case top, bottom, left, right
}

extension UIButton {

    public func addBorder(side: UIButtonBorderSide, color: UIColor, width: CGFloat) {
        let border = CALayer()
        border.backgroundColor = color.cgColor

        switch side {
        case .top:
            border.frame = CGRect(x: 0, y: 0, width: frame.size.width, height: width)
        case .bottom:
            border.frame = CGRect(x: 0, y: self.frame.size.height - width, width: self.frame.size.width, height: width)
        case .left:
            border.frame = CGRect(x: 0, y: 0, width: width, height: self.frame.size.height)
        case .right:
            border.frame = CGRect(x: self.frame.size.width - width, y: 0, width: width, height: self.frame.size.height)
        }

        self.layer.addSublayer(border)
    }
}

