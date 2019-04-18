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
        return try? me!.subscribe(set: nil, get: get)
    }

    // Get text from UITextField or mark the field red if the field is blank
    public static func ensureDataInTextField(_ field: UITextField) -> String {
        let text = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if (text.isEmpty) {
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

    // Resize image to given dimentions. If aspect ratios are different, clip the central part of the source
    // image and scale it down to the given dimentions.
    public static func resizeImage(image imageIn: UIImage?, width: Float, height: Float, clip: Bool) -> UIImage? {
        guard let image = imageIn else { return nil }

        guard let size = fitImageSize(originalWidth: Float(image.size.width), originalHeight: Float(image.size.height),
                                      maxWidth: width, maxHeight: height, clip: clip) else { return nil }

        // cropRect for cropping the original image to the required aspect ratio.
        let cropRect = CGRect(x: size.xOffset, y: size.yOffset, width: Int(size.srcWidth), height: Int(size.srcHeight))
        let scaleDown = CGAffineTransform(scaleX: CGFloat(size.dstWidth / size.srcWidth),
                                          y: CGFloat(size.dstWidth / size.srcWidth))

        // Scale image to the requested dimentions
        guard let imageOut = CIImage(image: image)?.cropped(to: cropRect).transformed(by: scaleDown) else { return nil }

        // This is some iOS weirdness. The image cannot be converted to png without it t.
        UIGraphicsBeginImageContext(imageOut.extent.size)
        defer { UIGraphicsEndImageContext() }
        UIImage(ciImage: imageOut).draw(in: CGRect(origin: .zero, size: imageOut.extent.size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // Calculate linear dimensions for scaling image down to fit under a certain size.
    // Returns an tuple which contains destination image sizes, source sizes, and offsets
    // into source (when 'clip' is true).
    //
    // The 'clip' parameter forces image to have the new dimensions. Otherwise the
    // image keeps the original aspect ratio with width and hight being under the
    // maxWindth/maxHeight
    public static func fitImageSize(originalWidth: Float, originalHeight: Float, maxWidth: Float, maxHeight: Float, clip: Bool) -> (dstWidth: Float, dstHeight: Float, xOffset: Int, yOffset: Int, srcWidth: Float, srcHeight: Float)? {

        // Sanity check
        if originalWidth <= 0 || originalHeight <= 0 || maxWidth <= 0 || maxHeight <= 0 {
            return nil
        }

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
