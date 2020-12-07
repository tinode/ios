//
//  AsyncTextAttachment.swift
//  Tinodios
//
//  Copyright © 2020 Tinode. All rights reserved.
//

import Kingfisher
import TinodeSDK
import UIKit

/// An image text attachment which gets updated after loading an imgae from URL
public class AsyncTextAttachment: NSTextAttachment {
    /// Container to be notified when the image is updated: successfully fetched or failed.
    weak var textContainer: NSTextContainer?

    /// Source of the image
    public var url: URL

    /// Designated initializer
    public init(url: URL) {
        self.url = url

        super.init(data: nil, ofType: nil)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }

    public func startDownload(onError errorImage: UIImage) {
        let modifier = AnyModifier { request in
            var request = request
            LargeFileHelper.addCommonHeaders(to: &request, using: Cache.tinode)
            return request
        }

        KingfisherManager.shared.retrieveImage(with: url.downloadURL, options: [.requestModifier(modifier)], completionHandler: { result in
            switch result {
            case .success(let value):
                self.image = value.image
            case .failure(let error):
                self.image = errorImage
                Cache.log.info("Failed to download image '%@': %d", self.url.absoluteString, error.errorCode)
            }

            DispatchQueue.main.async {
                // Force container redraw.
                let length = self.textContainer?.layoutManager?.textStorage?.length
                self.textContainer?.layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: length ?? 1))
            }
        })
    }

    public override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {
        // Keep reference to text container. It will be updated if image changes.
        self.textContainer = textContainer
        return image
    }
}
