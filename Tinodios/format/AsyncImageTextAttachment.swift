//
//  AsyncTextAttachment.swift
//
//  Copyright © 2020-2022 Tinode LLC. All rights reserved.
//

import TinodeSDK
import UIKit

/// An image text attachment which gets updated after loading an image from URL.
public class AsyncImageTextAttachment: EntityTextAttachment {
    /// Container to be notified when the image is updated: successfully fetched or failed.
    private weak var textContainer: NSTextContainer?

    /// Source of the image
    public var url: URL

    /// Postprocessing callback after the image's been downloaded
    private var postprocessing: ((UIImage) -> UIImage?)?

    /// Designated initializer
    public init(url: URL, afterDownloaded: ((UIImage) -> UIImage?)? = nil) {
        self.url = url
        self.postprocessing = afterDownloaded

        super.init(data: nil, ofType: nil)
        self.type = "image"
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }

    public func startDownload(onError errorImage: UIImage) {
        Utils.fetchTinodeResource(from: url)
            .then(onSuccess: { value in
                if let done = self.postprocessing {
                    self.image = done(value!) ?? errorImage
                } else {
                    self.image = value
                }
                return nil
            }, onFailure: { error in
                self.image = errorImage
                Cache.log.info("Failed to download image '%@': %@", self.url.absoluteString, error.localizedDescription)
                return nil
            })
            .thenFinally {
                DispatchQueue.main.async {
                    // Force container redraw.
                    let length = self.textContainer?.layoutManager?.textStorage?.length
                    self.textContainer?.layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: length ?? 1))
                }
            }
    }

    public override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {
        // Keep reference to text container. It will be updated if image changes.
        self.textContainer = textContainer
        return image
    }
}
