//
//  MultistateImageTextAttachment.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import TinodeSDK
import UIKit

/// An image text attachment with multiple images and ability to flip through them.
public class MultiImageTextAttachment: EntityTextAttachment {
    /// Container to be notified when the image is updated: successfully fetched or failed.
    private weak var textContainer: NSTextContainer?

    var images: [UIImage]
    var index: Int = 0

    /// Designated initializer
    public init(images: [UIImage]) {
        self.images = images
        super.init(data: nil, ofType: nil)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }

    /// Show the next image in stack. If the end is reached, go back to the first image.
    public func next() {
        index = (index + 1) % images.count
        DispatchQueue.main.async {
            // Force container redraw.
            let length = self.textContainer?.layoutManager?.textStorage?.length
            self.textContainer?.layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: length ?? 1))
        }
    }

    public override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {
        // Keep reference to text container. It will be updated if image changes.
        self.textContainer = textContainer
        return images[index]
    }
}

