//
//  ThumbnailTransformer.swift
//  Tinodios
//
//  Copyright © 2022 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

// Turns images into thumbnails when preparing a reply quote to a message.
 public class ThumbnailTransformer: DraftyTransformer {
     // Keeps track of the chain of images which need to be asynchronously downloaded
     // and downsized.
     var promise: PromisedReply<UIImage>?

     required public init() {}

     public func transform(node: Drafty.Span) -> Drafty.Span? {
         guard node.type == "IM" else {
             return node
         }

         let result = Drafty.Span(from: node)
         if result.data != nil {
             result.data?.removeAll()
         } else {
             result.data = [:]
         }
         result.data!["name"] = node.data?["name"]
         if let bits = node.data?["val"]?.asData() {
             let thumbnail = UIImage(data: bits)?.resize(
                 width: CGFloat(UiUtils.kReplyThumbnailSize), height: CGFloat(UiUtils.kReplyThumbnailSize), clip: true)
             let thumbnailBits = thumbnail?.pixelData(forMimeType: "image/jpeg")
             result.data!["val"] = .bytes(thumbnailBits!)
             result.data!["mime"] = .string("image/jpeg")
             result.data!["size"] = .int(thumbnailBits!.count)
         } else if let ref = node.data?["ref"]?.asString() {
             let origPromise = self.promise
             let url = Utils.tinodeResourceUrl(from: ref)
             let p = Utils.fetchTinodeResource(from: url)?.thenApply {
                 let thumbnail = $0?.resize(
                     width: CGFloat(UiUtils.kReplyThumbnailSize), height: CGFloat(UiUtils.kReplyThumbnailSize), clip: true)
                 let thumbnailBits = thumbnail?.pixelData(forMimeType: "image/jpeg")
                 result.data!["val"] = .bytes(thumbnailBits!)
                 result.data!["mime"] = .string("image/jpeg")
                 return origPromise
             }
             // Chain promises.
             self.promise = p
         }
         result.data!["width"] = .int(UiUtils.kReplyThumbnailSize)
         result.data!["height"] = .int(UiUtils.kReplyThumbnailSize)
         return result
     }
 }
