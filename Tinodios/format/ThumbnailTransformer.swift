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
         var bitsField: String
         var refField: String
         var maxWidth: Int
         var maxHeight: Int
         var forceSquare = false
         switch node.type {
         case "IM":
             bitsField = "val"
             refField = "ref"
             maxWidth = UiUtils.kReplyThumbnailSize
             maxHeight = UiUtils.kReplyThumbnailSize
             forceSquare = true
         case "VD":
             bitsField = "preview"
             refField = "preref"
             maxWidth = UiUtils.kReplyVideoThumbnailWidth
             maxHeight = UiUtils.kReplyThumbnailSize
         default:
             return node
         }

         let result = Drafty.Span(from: node)
         result.type = "IM"
         if result.data != nil {
             result.data?.removeAll()
         } else {
             result.data = [:]
         }

         var actualSize: CGSize = CGSize(width: UiUtils.kReplyThumbnailSize, height: UiUtils.kReplyThumbnailSize)
         if let w = node.data?["width"]?.asInt(), let h = node.data?["height"]?.asInt() {
             actualSize = UiUtils.sizeUnder(original: CGSize(width: w, height: h), fitUnder: CGSize(width: maxWidth, height: maxHeight), scale: 1, clip: false).dst
         }
         if let bits = node.data?[bitsField]?.asData() {
             let thumbnail = UIImage(data: bits)?.resize(
                 width: CGFloat(maxWidth), height: CGFloat(maxHeight), clip: true)
             if let thumbnailBits = thumbnail?.pixelData(forMimeType: "image/jpeg") {
                 result.data!["val"] = .bytes(thumbnailBits)
                 result.data!["mime"] = .string("image/jpeg")
                 result.data!["size"] = .int(thumbnailBits.count)
             } else {
                 Log.default.info("Failed to create thumbnail from data[val]")
             }
         } else if let ref = node.data?[refField]?.asString() {
             if self.promises == nil {
                 self.promises = []
             }
             let done = Utils.fetchTinodeResource(from: Utils.tinodeResourceUrl(from: ref)).thenApply {
                 let thumbnail = $0?.resize(
                     width: CGFloat(maxWidth), height: CGFloat(maxHeight), clip: true)
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
         result.data!["width"] = .int(forceSquare ? UiUtils.kReplyThumbnailSize : Int(actualSize.width))
         result.data!["height"] = .int(forceSquare ? UiUtils.kReplyThumbnailSize : Int(actualSize.height))
         return result
     }
 }
