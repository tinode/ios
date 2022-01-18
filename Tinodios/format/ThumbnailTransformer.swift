//
//  ThumbnailTransformer.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import Foundation
import TinodeSDK

// Turns images into thumbnails when preparing a reply quote to a message.
 public class ThumbnailTransformer: DraftyTransformer {
     // Keeps track of the chain of images which need to be asynchronously downloaded
     // and downsized.
     var promises: [PromisedReply<UIImage>]?

     required public init() {}

     public var completionPromise: PromisedReply<Void> {
         guard let promises = self.promises else {
             return PromisedReply<Void>(value: Void())
         }
         return PromisedReply.allOf(promises: promises)
     }

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

         if let bits = node.data?["val"]?.asData() {
             let thumbnail = UIImage(data: bits)?.resize(
                 width: CGFloat(UiUtils.kReplyThumbnailSize), height: CGFloat(UiUtils.kReplyThumbnailSize), clip: true)
             if let thumbnailBits = thumbnail?.pixelData(forMimeType: "image/jpeg") {
                 result.data!["val"] = .bytes(thumbnailBits)
                 result.data!["mime"] = .string("image/jpeg")
                 result.data!["size"] = .int(thumbnailBits.count)
             } else {
                 Log.default.info("Failed to create thumbnail from data[val]")
             }
         } else if let ref = node.data?["ref"]?.asString() {
             if self.promises == nil {
                 self.promises = []
             }
             let done = Utils.fetchTinodeResource(from: Utils.tinodeResourceUrl(from: ref)).thenApply {
                 let thumbnail = $0?.resize(
                     width: CGFloat(UiUtils.kReplyThumbnailSize), height: CGFloat(UiUtils.kReplyThumbnailSize), clip: true)
                 if let thumbnailBits = thumbnail?.pixelData(forMimeType: "image/jpeg") {
                     result.data!["val"] = .bytes(thumbnailBits)
                     result.data!["mime"] = .string("image/jpeg")
                     result.data!["size"] = .int(thumbnailBits.count)
                 }
                 return nil
             }
             self.promises!.append(done)
         }

         result.data!["name"] = node.data?["name"]
         result.data!["width"] = .int(UiUtils.kReplyThumbnailSize)
         result.data!["height"] = .int(UiUtils.kReplyThumbnailSize)
         return result
     }
 }
