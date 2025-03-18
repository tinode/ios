//
//  Utils.swift
//  Tinodios
//
//  Copyright © 2019-2025 Tinode. All rights reserved.
//

import Foundation
import Kingfisher
import MobileCoreServices
import PhoneNumberKit
import TinodeSDK
import TinodiosDB

public class Utils {
    public static let kTopicUriPrefix = "tinode:topic/"

    static var phoneNumberKit: PhoneNumberUtility = {
        return PhoneNumberUtility()
    }()

    // Calculate difference between two arrays of messages. Returns a tuple of insertion indexes and deletion indexes.
    // First the deletion indexes are applied to the old array. Then insertions are applied to the remaining array.
    // Indexes should be applied in descending order.
    public static func diffMessageArray(sortedOld old: [Message], sortedNew new: [Message]) -> (inserted: [Int], removed: [Int], mutated: [Int]) {
        if old.isEmpty && new.isEmpty {
            return (inserted: [], removed: [], mutated: [])
        }
        if old.isEmpty {
            return (inserted: Array(0 ..< new.count), removed: [], mutated: Array(0 ..< new.count))
        }
        if new.isEmpty {
            return (inserted: [], removed: Array(0 ..< old.count), mutated: [])
        }

        var removed: [Int] = []
        var inserted: [Int] = []
        var mutated: [Int] = []

        // Match old array against the new array to separate removed items from inserted.
        var o = 0, n = 0
        while o < old.count || n < new.count {
            if o == old.count || (n < new.count && old[o].seqId > new[n].seqId) {
                // Present in new, missing in old: added
                inserted.append(n)
                if mutated.last ?? -1 != n {
                    mutated.append(n)
                }
                n += 1

            } else if n == new.count || old[o].seqId < new[n].seqId {
                // Present in old, missing in new: removed
                removed.append(o)
                if mutated.last ?? -1 != n && n < new.count {
                    // Appending n, not o because mutated is an index agaist the new data.
                    mutated.append(n)
                }
                o += 1

            } else {
                // present in both
                if o < old.count && n < new.count && !old[o].equals(new[n]) {
                    mutated.append(n)
                }
                if o < old.count {
                    o += 1
                }
                if n < new.count {
                    n += 1
                }
            }
        }

        return (inserted: inserted, removed: removed, mutated: mutated)
    }

    public static func isValidTag(tag: String) -> Bool {
        let minTagLength = Cache.tinode.getServerLimit(for: Tinode.kMinTagLength, withDefault: UiUtils.kMinTagLength)
        let maxTagLength = Cache.tinode.getServerLimit(for: Tinode.kMaxTagLength, withDefault: UiUtils.kMaxTagLength)
        return tag.count >= minTagLength && tag.count <= maxTagLength
    }

    public static func uniqueFilename(forMime mime: String?) -> String {
        let mimeType: CFString = (mime ?? "application/octet-stream") as CFString
        var ext: String?
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType, nil)?.takeUnretainedValue() {
            ext = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassFilenameExtension)?.takeUnretainedValue() as String?
        }
        return ProcessInfo.processInfo.globallyUniqueString + "." + (ext ?? "bin")
    }

    public static func mimeForUrl(url: URL, ifMissing: String = "application/octet-stream") -> String {
        if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier {
            let unmanaged = UTTypeCopyPreferredTagWithClass(uti as CFString, kUTTagClassMIMEType)
            return unmanaged?.takeRetainedValue() as String? ?? ifMissing
        }
        return ifMissing
    }

    public static func fetchTopics(archived: Bool) -> [DefaultComTopic]? {
        return Cache.tinode.getFilteredTopics(filter: {(topic: TopicProto) in
            return topic.topicType.matches(TopicType.user) && topic.isArchived == archived && topic.isJoiner
        })?.map {
            // Must succeed.
            $0 as! DefaultComTopic
        }
    }

    // Creates a URL out of Tinode ref.
    public static func tinodeResourceUrl(from ref: String) -> URL? {
        let u = URL(string: ref, relativeTo: Cache.tinode.baseURL(useWebsocketProtocol: false))
        return u
    }

    // Initializes a download for a resource (typically, an image) from the provided url.
    public static func fetchTinodeResource(from url: URL?) -> PromisedReply<UIImage> {
        let modifier = AnyModifier { request in
            var request = request
            LargeFileHelper.addCommonHeaders(to: &request, using: Cache.tinode)
            return request
        }
        let p = PromisedReply<UIImage>()
        KingfisherManager.shared.retrieveImage(with: url!.downloadURL, options: [.requestModifier(modifier)], completionHandler: { result in
            switch result {
            case .success(let value):
                try? p.resolve(result: value.image)
            case .failure(let error):
                try? p.reject(error: error)
            }
        })
        return p
    }

    public static func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: String.Encoding.ascii)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }

        filter.setValue(data, forKey: "inputMessage")

        guard let qrcode = filter.outputImage else { return nil }

        // QR code is very small. Scaling it up without smoothing.
        let scaledImageSize = qrcode.extent.size.applying(CGAffineTransform(scaleX: 3, y: 3))
        UIGraphicsBeginImageContext(scaledImageSize)
        let scaledContext = UIGraphicsGetCurrentContext()!
        scaledContext.interpolationQuality = .none
        UIImage(ciImage: qrcode).draw(in: CGRect(origin: .zero, size: scaledImageSize))
        return UIGraphicsGetImageFromCurrentImageContext()!
    }
}

// Per
// https://medium.com/over-engineering/a-background-repeating-timer-in-swift-412cecfd2ef9
class RepeatingTimer {
    let timeInterval: TimeInterval
    init(timeInterval: TimeInterval) {
        self.timeInterval = timeInterval
    }
    private lazy var timer: DispatchSourceTimer = {
        let t = DispatchSource.makeTimerSource()
        t.schedule(deadline: .now() + self.timeInterval, repeating: self.timeInterval)
        t.setEventHandler(handler: { [weak self] in
            self?.eventHandler?()
        })
        return t
    }()
    var eventHandler: (() -> Void)?
    public enum State {
        case suspended
        case resumed
    }
    public var state: State = .suspended
    deinit {
        timer.setEventHandler {}
        timer.cancel()
        // If the timer is suspended, calling cancel without resuming
        // triggers a crash. This is documented here
        // https://forums.developer.apple.com/thread/15902
        resume()
        eventHandler = nil
    }

    func resume() {
        if state == .resumed {
            return
        }
        state = .resumed
        timer.resume()
    }

    func suspend() {
        if state == .suspended {
            return
        }
        state = .suspended
        timer.suspend()
    }
}

class RelativeDateFormatter {
    // DateFormatter is thread safe, OK to keep a copy.
    static let shared = RelativeDateFormatter()

    private let formatter = DateFormatter()

    func dateOnly(from date: Date?, style: DateFormatter.Style = .medium) -> String {
        guard let date = date else { return NSLocalizedString("Never ??:??", comment: "Invalid date") }

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

    // Incrementally longer formatting of a date.
    func shortDate(from date: Date?) -> String {
        guard let date = date else { return NSLocalizedString("Never ??:??", comment: "Invalid date") }

        let now = Date()
        if Calendar.current.isDate(date, equalTo: now, toGranularity: .year) {
            if Calendar.current.isDate(date, equalTo: now, toGranularity: .day) {
                formatter.timeStyle = .short
                formatter.dateStyle = .none
                return formatter.string(from: date)
            } else {
                formatter.timeStyle = .short
                formatter.dateStyle = .short
                return formatter.string(from: date)
            }
        }

        formatter.timeStyle = .medium
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

extension URL {
    public func extractQueryParam(named name: String) -> String? {
        let components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == name })?.value
    }

    // Attempt to convert the given URL to a relative URL using 'from' as the base.
    func relativize(from base: URL) -> String {
        // Ensure that both URLs share the scheme (protocol) and authority:
        guard self.scheme == base.scheme && self.host == base.host && self.port == base.port &&
                self.user == base.user && self.password == base.password else {
            return self.absoluteString
        }

        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self.absoluteString
        }

        return "\(components.path)?\(components.query ?? "")"
    }
}

extension UIFont {
    func withTraits(traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return UIFont(descriptor: descriptor!, size: 0) // size 0 means keep the size as it is
    }
}

extension StoredMessage {
    static var previewFormatter: AbstractFormatter?

    /// Generate and cache NSAttributedString representation of Drafty content.
    func attributedContent(fitIn size: CGSize, withDefaultAttributes attributes: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString? {
        guard cachedContent == nil else { return cachedContent }
        if !isDeleted {
            guard let content = content else { return nil }
            cachedContent = FullFormatter(defaultAttributes: attributes ?? [:]).toAttributed(content, fitIn: size)
        } else {
            cachedContent = StoredMessage.contentDeletedMessage(withAttributes: attributes)
        }
        return cachedContent
    }

    /// Generate and cache NSAttributedString preview of Drafty content.
    func attributedPreview(fitIn size: CGSize, withDefaultAttributes attributes: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString? {
        guard cachedPreview == nil else { return cachedPreview }
        if !isDeleted {
            guard var content = content else { return nil }
            if StoredMessage.previewFormatter == nil {
                StoredMessage.previewFormatter = PreviewFormatter(defaultAttributes: [:])
            }
            content = content.preview(previewLen: UiUtils.kPreviewLength)
            cachedPreview = StoredMessage.previewFormatter!.toAttributed(content, fitIn: size)
        } else {
            cachedPreview = StoredMessage.contentDeletedMessage(withAttributes: attributes)
        }
        return cachedPreview
    }

    /// Creates "content deleted" string with a small "blocked" icon.
    private static func contentDeletedMessage(withAttributes attr: [NSAttributedString.Key: Any]?) -> NSAttributedString {
        // Space is needed as a workaround for a bug in UIKit. The icon style is not applied if the icon is the first object in the attributed string.
        let second = NSMutableAttributedString(string: " ")
        second.beginEditing()

        // Add 'block' icon.
        let icon = NSTextAttachment()
        icon.image = UIImage(systemName: "nosign")?.withRenderingMode(.alwaysTemplate)
        // Make image smaller
        icon.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
        second.append(NSAttributedString(attachment: icon))
        if let attr = attr {
            // apply tint color to image
            second.addAttributes(attr, range: NSRange(location: 0, length: second.length))
        }
        // Align image and text vertically per
        // https://stackoverflow.com/questions/47844721/vertically-aligning-nstextattachment-in-nsmutableattributedstring
        var textFont: UIFont = attr?[.font] as? UIFont ?? UIFont.systemFont(ofSize: 14)
        textFont = textFont.withSize(14)
        var newAttr: [NSAttributedString.Key: Any] = attr ?? [:]
        newAttr[.baselineOffset] = (icon.bounds.height - textFont.pointSize) / 2 - textFont.descender / 2
        newAttr[.font] = textFont
        second.append(NSAttributedString(string: NSLocalizedString("  Content deleted", comment: "Replacement for chat message with no content"), attributes: newAttr))
        second.endEditing()
        return second
    }

    // Returns true if message contains an inline image.
    var isVisualMedia: Bool {
        guard let ents = self.content?.entities else { return false }
        return ents.contains {
            ["IM", "VD"].contains($0.tp)
        }
    }
}

extension Date {
    var millisecondsSince1970: Int64 {
        return Int64((self.timeIntervalSince1970 * 1000.0).rounded())
    }
}

extension TimeInterval {
    var asDurationString: String {
        return String(format: "%02d:%02d", Int(self / 60), Int(self.truncatingRemainder(dividingBy: 60)))
    }
}

extension Tinode {
    func getRequiredCredMethods(forAuthLevel authLevel: String) -> [String]? {
        guard case let .dict(allCred) = self.getServerParam(for: "reqCred") else {
            return nil
        }
        if let allMeth = allCred[authLevel], case let .array(meth) = allMeth {
            return meth.map { $0.asString() ?? "" }.filter { !$0.isEmpty }
        }
        return nil
    }
}

extension Character {
    var isEmoji: Bool {
        guard let firstScalar = unicodeScalars.first else {
            return false
        }
        return firstScalar.properties.isEmoji && (unicodeScalars.count > 1 || firstScalar.value > 0x238C)
    }
}

extension String {
    var isEmojiOnly: Bool { !isEmpty && !contains { !$0.isEmoji } }
}

extension DefaultComTopic {
    // Returns true if the topic allows calls to be placed.
    var callsAllowed: Bool {
        let t = Cache.tinode
        // The user is allowed to post messages and
        // - for p2p topics, we have ice servers to establish communication via.
        // - for group topics, we have media server endpoint.
        return self.isWriter && (self.isP2PType && t.getServerParam(for: "iceServers") != nil)
            // || (self.isGrpType && t.getServerParam(for: "vcEndpoint") != nil))
    }
}

extension CGRect {
    // Splits self into two rectangles measuring `fraction` (between 0..1) from the specified edge
    func dividedIntegral(fraction: CGFloat, from fromEdge: CGRectEdge) -> (first: CGRect, second: CGRect) {
        let dimension: CGFloat

        switch fromEdge {
        case .minXEdge, .maxXEdge:
            dimension = self.size.width
        case .minYEdge, .maxYEdge:
            dimension = self.size.height
        }

        let distance = (dimension * fraction).rounded(.up)
        var slices = self.divided(atDistance: distance, from: fromEdge)

        switch fromEdge {
        case .minXEdge, .maxXEdge:
            slices.remainder.origin.x += 1
            slices.remainder.size.width -= 1
        case .minYEdge, .maxYEdge:
            slices.remainder.origin.y += 1
            slices.remainder.size.height -= 1
        }

        return (first: slices.slice, second: slices.remainder)
    }
}
