//
//  Drafty.swift
//  ios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit

public enum DraftyError: Error {
    case illegalArgument(String)
    case invalidIndex(String)
}

// Basic unit of the Drafty formatting tree which
// defines how a given span of text should be formatted.
public protocol DraftySpan {
    init()
    func append(_ child: DraftySpan)
}

// Describes a class which constructs a Drafty formatting tree
// (which consists of DraftyNode{s}).
public protocol DraftyFormatter {
    func apply(tp: String?, attr: [String: JSONValue]?, content: [DraftySpan]) -> DraftySpan
    func apply(tp: String?, attr: [String: JSONValue]?, content: String?) -> DraftySpan

    // Formatting type handlers.
    func handleStrong(withText content: String?, withChildren nodes: [DraftySpan]?) -> DraftySpan
    func handleEmphasized(withText content: String?, withChildren nodes: [DraftySpan]?) -> DraftySpan
    func handleDeleted(withText content: String?, withChildren nodes: [DraftySpan]?) -> DraftySpan
    func handleCode(withText content: String?, withChildren nodes: [DraftySpan]?) -> DraftySpan
    func handleHidden(withText content: String?, withChildren nodes: [DraftySpan]?) -> DraftySpan
    func handleLineBreak() -> DraftySpan
    func handleLink(withText content: String?, withChildren nodes: [DraftySpan]?, attr: [String: JSONValue]?) -> DraftySpan
    func handleMention(withText content: String?, withChildren nodes: [DraftySpan]?, using attr: [String: JSONValue]?) -> DraftySpan
    func handleHashtag(withText content: String?, withChildren nodes: [DraftySpan]?) -> DraftySpan
    func handleImage(withText content: String?, withChildren nodes: [DraftySpan]?, using attr: [String: JSONValue]?) -> DraftySpan
    func handleAttachment(withText content: String?, withChildren nodes: [DraftySpan]?, using attr: [String: JSONValue]?) -> DraftySpan
    func handleButton(withText content: String?, withChildren nodes: [DraftySpan]?, using attr: [String: JSONValue]?) -> DraftySpan
    func handleForm(withText content: String?, withChildren nodes: [DraftySpan]?) -> DraftySpan
    func handleFormRow(withText content: String?, withChildren nodes: [DraftySpan]?) -> DraftySpan
    func handleUnknown(withText content: String?, withChildren nodes: [DraftySpan]?) -> DraftySpan
    func handlePlain(withText content: String?, withChildren nodes: [DraftySpan]?) -> DraftySpan
    func handleQuote(withText content: String?, withChildren nodes: [DraftySpan]?) -> DraftySpan
}

extension DraftyFormatter {
    // Construct a tree representing formatting styles and content.
    public func makeTree(tp: String?, attr: [String: JSONValue]?, children: [DraftySpan]?, content: String?) -> DraftySpan {
        guard let tp = tp else {
            return handlePlain(withText: content, withChildren: children)
        }
        switch tp {
        case "ST":
            return handleStrong(withText: content, withChildren: children)
        case "EM":
            return handleEmphasized(withText: content, withChildren: children)
        case "DL":
            return handleDeleted(withText: content, withChildren: children)
        case "CO":
            return handleCode(withText: content, withChildren: children)
        case "BR":
            return handleLineBreak()
        case "LN":
            return handleLink(withText: content, withChildren: children, attr: attr)
        case "MN":
            return handleMention(withText: content, withChildren: children, using: attr)
        case "HT":
            return handleHashtag(withText: content, withChildren: children)
        case "HD":
            return handleHidden(withText: content, withChildren: children)
        case "IM":
            return handleImage(withText: content, withChildren: children, using: attr)
        case "EX":
            return handleAttachment(withText: content, withChildren: children, using: attr)
        case "BN":
            return handleButton(withText: content, withChildren: children, using: attr) // (from: node, with: attr)
        case "FM":
            return handleForm(withText: content, withChildren: children)
        case "RW":
            return handleFormRow(withText: content, withChildren: children)
        case "QQ":
            return handleQuote(withText: content, withChildren: children)
        default:
            return handleUnknown(withText: content, withChildren: children)
        }
    }
}

// Span tree transformer interface.
public protocol SpanTreeTransformer {
    // Called on every node of the span tree.
    // Returns a new node that the given node should be replaced with.
    func transform(node: Drafty.Span) -> Drafty.Span?
}

/// Class representing formatted text with optional attachments.
open class Drafty: Codable, CustomStringConvertible, Equatable {
    public static let kMimeType = "text/x-drafty"
    public static let kJSONMimeType = "application/json"

    private static let kMaxFormElements = 8

    // Regular expressions for parsing inline formats.
    private static let kInlineStyles = try! [
        "ST": NSRegularExpression(pattern: #"(?<=^|[\W_])\*([^*]+[^\s*])\*(?=$|[\W_])"#), // bold *bo*
        "EM": NSRegularExpression(pattern: #"(?<=^|\W)_([^_]+[^\s_])_(?=$|\W)"#),         // italic _it_
        "DL": NSRegularExpression(pattern: #"(?<=^|[\W_])~([^~]+[^\s~])~(?=$|[\W_])"#),   // strikethough ~st~
        "CO": NSRegularExpression(pattern: #"(?<=^|\W)`([^`]+)`(?=$|\W)"#)                // code/monospace `mono`
    ]

    private static let kEntities = try! [
        EntityProc(name: "LN",
                   pattern: NSRegularExpression(pattern: #"\b(https?://)?(?:www\.)?(?:[a-z0-9][-a-z0-9]*[a-z0-9]\.){1,5}[a-z]{2,6}(?:[/?#:][-a-z0-9@:%_+.~#?&/=]*)?"#, options: [.caseInsensitive]),
                   pack: {(text: NSString, m: NSTextCheckingResult) -> [String: JSONValue] in
                        var data: [String: JSONValue] = [:]
                        data["url"] = JSONValue.string(m.range(at: 1).location == NSNotFound ? "http://" + text.substring(with: m.range) : text.substring(with: m.range))
                        return data
                   }),
        EntityProc(name: "MN",
                   pattern: NSRegularExpression(pattern: #"\B@(\w\w+)"#),
                   pack: {(text: NSString, m: NSTextCheckingResult) -> [String: JSONValue] in
                    var data: [String: JSONValue] = [:]
                    data["val"] = JSONValue.string(text.substring(with: m.range(at: 1)))
                    return data
            }),
        EntityProc(name: "HT",
                   pattern: NSRegularExpression(pattern: #"(?<=[\s,.!]|^)#(\w\w+)"#),
                   pack: {(text: NSString, m: NSTextCheckingResult) -> [String: JSONValue] in
                    var data: [String: JSONValue] = [:]
                    data["val"] = JSONValue.string(text.substring(with: m.range(at: 1)))
                    return data
            })
    ]

    private enum CodingKeys: String, CodingKey {
        case txt = "txt"
        case fmt = "fmt"
        case ent = "ent"
    }

    public var txt: String
    public var fmt: [Style]?
    public var ent: [Entity]?

    public var hasRefEntity: Bool {
        guard let ent = ent, ent.count > 0 else { return false }
        return ent.first(where: { $0.data?["ref"] != nil }) != nil
    }

    private var length: Int { return txt.count }

    /// Initializes empty object
    public init() {
        txt = ""
    }

    /// Initializer to comply with Decodable protocol:
    /// First tries to decode Drafty from plain text, then
    /// from from JSON.
    required public init(from decoder: Decoder) throws {
        // First try optional decoding of 'txt' from a primitive string.
        // Most content is sent as primitive strings.
        if let container = try? decoder.singleValueContainer(),
            let txt = try? container.decode(String.self) {
            self.txt = txt
        } else {
            // Non-optional decoding as a Drafty object.
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Txt is missing for attachments. 
            do {
                txt = try container.decode(String.self, forKey: .txt)
            } catch DecodingError.keyNotFound {
                txt = ""
            }
            fmt = try? container.decode([Style].self, forKey: .fmt)
            ent = try? container.decode([Entity].self, forKey: .ent)
        }
    }

    /// encode makes Drafty compliant with Encodable protocol.
    /// First checks if Drafty can be represented as plain text and if so encodes
    /// it as a primitive string. Otherwise encodes into a JSON object.
    public func encode(to encoder: Encoder) throws {
        if isPlain {
            // If trafty contains plain text, encode it as a primitive string.
            var container = encoder.singleValueContainer()
            try container.encode(txt)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(txt, forKey: CodingKeys.txt)
            // fmt cannot be nil.
            try container.encode(fmt, forKey: CodingKeys.fmt)
            // Encode entities only if they are present.
            if ent != nil {
                try container.encode(ent, forKey: CodingKeys.ent)
            }
        }
    }

    /// Parses provided content string using markdown-like markup.
    ///
    /// - Parameters:
    ///     - content: a string with optional markdown-style markup
    public init(content: String) {
        let that = Drafty.parse(content: content)

        self.txt = that.txt
        self.fmt = that.fmt
        self.ent = that.ent
    }

    /// Initializes Drafty without parsing the text string.
    /// - Parameters:
    ///     - plainText: text body
    public init(plainText: String) {
        txt = plainText
    }

    /// Initializes Drafty with text and formatting obeject without parsing the text string.
    /// - Parameters:
    ///     - text: text body
    ///     - fmt: array of inline styles and references to entities
    ///     - ent: array of entity attachments
    init(text: String, fmt: [Style]?, ent: [Entity]?) {
        self.txt = text
        self.fmt = fmt
        self.ent = ent
    }

    // Detect starts and ends of formatting spans. Unformatted spans are
    // ignored at this stage.
    private static func spannify(original: String, re: NSRegularExpression, type: String) -> [Span] {
        var spans: [Span] = []
        let nsoriginal = original as NSString
        let matcher = re.matches(in: original, range: NSRange(location: 0, length: nsoriginal.length))
        for match in matcher {
            let s = Span()
            // Convert NSRange to Range otherwise it will fail on strings with characters not
            // representable in UTF16 (i.e. emoji)
            var r = Range(match.range, in: original)!
                        // ^ match.range.lowerBound -> index of the opening markup character
            s.start = original.distance(from: original.startIndex, to: r.lowerBound) // 'hello *world*'
            s.text = nsoriginal.substring(with: match.range(at: 1))
            r = Range(match.range(at: 1), in: original)!
            s.end = original.distance(from: original.startIndex, to: r.upperBound)
            s.type = type
            spans.append(s)
        }
        return spans
    }

    // Take a string and defined earlier style spans, re-compose them into a tree where each leaf is
    // a same-style (including unstyled) string. I.e. 'hello *bold _italic_* and ~more~ world' ->
    // ('hello ', (b: 'bold ', (i: 'italic')), ' and ', (s: 'more'), ' world');
    //
    // This is needed in order to clear markup, i.e. 'hello *world*' -> 'hello world' and convert
    // ranges from markup-ed offsets to plain text offsets.
    private static func chunkify(line: String, start startAt: Int, end: Int, spans: [Span]) -> [Span] {
        guard !spans.isEmpty else { return spans }

        var start = startAt
        var chunks: [Span] = []
        for span in spans {
            // Grab the initial unstyled chunk.
            if span.start > start {
                // Substrings in Swift are crazy.
                chunks.append(Span(text: String(line[line.index(line.startIndex, offsetBy: start)..<line.index(line.startIndex, offsetBy: span.start)])))
            }

            // Grab the styled chunk. It may include subchunks.
            let chunk = Span()
            chunk.type = span.type

            if let children = span.children {
                chunk.children = chunkify(line: line, start: span.start + 1, end: span.end, spans: children)
            } else {
                chunk.text = span.text
            }

            chunks.append(chunk)
            start = span.end + 1 // '+1' is to skip the formatting character
        }

        // Grab the remaining unstyled chunk, after the last span
        if start < end {
            chunks.append(Span(text: String(line[line.index(line.startIndex, offsetBy: start)..<line.index(line.startIndex, offsetBy: end)])))
        }

        return chunks
    }

    // Convert flat array or spans into a tree representation.
    // Keep standalone and nested spans, throw away partially overlapping spans.
    private static func toTree(spans: [Span]) -> [Span] {
        guard !spans.isEmpty else { return spans }

        var tree: [Span] = []

        var last = spans[0]
        tree.append(last)
        for i in 1..<spans.count {
            let curr = spans[i]
            // Keep spans which start after the end of the previous span or those which
            // are complete within the previous span.
            if curr.start > last.end {
                // Span is completely outside of the previous span.
                tree.append(curr)
                last = curr
            } else if curr.end < last.end {
                // Span is fully inside of the previous span. Push to subnode.
                if last.children == nil {
                    last.children = []
                }
                last.children!.append(curr)
            }
            // Span could also partially overlap, ignore it as invalid.
        }

        // Recursively rearrange the subnodes.
        for span in tree {
            if let children = span.children {
                span.children = toTree(spans: children)
            }
        }

        return tree
    }

    // Convert a list of chunks into a block. A block fully describes one line of formatted text.
    private static func draftify(chunks: [Span]?, startAt: Int) -> Block? {
        guard let chunks = chunks else { return nil }

        let block = Block(txt: "")
        var ranges: [Style] = []
        for chunk in chunks {
            if chunk.text == nil {
                if let drafty = draftify(chunks: chunk.children, startAt: block.txt.count + startAt) {
                    chunk.text = drafty.txt
                    if let fmt = drafty.fmt {
                        ranges.append(contentsOf: fmt)
                    }
                }
            }

            if chunk.type != nil {
                ranges.append(Style(tp: chunk.type, at: block.txt.count + startAt, len: chunk.text!.count))
            }

            if chunk.text != nil {
                block.txt += chunk.text!
            }
        }

        if ranges.count > 0 {
            block.fmt = ranges
        }

        return block
    }

    // Extract entities from a line of text.
    private static func extractEntities(line: String) -> [ExtractedEnt] {
        let nsline = line as NSString
        return Drafty.kEntities.flatMap { (proc: EntityProc) -> [ExtractedEnt] in
            let matches = proc.re.matches(in: line, range: NSRange(location: 0, length: nsline.length))
            return matches.map { (m) -> ExtractedEnt in
                let ee = ExtractedEnt()
                // m.range is the entire match including markup
                let r = Range(m.range, in: line)!
                ee.at = line.distance(from: line.startIndex, to: r.lowerBound)
                ee.value = nsline.substring(with: m.range)
                ee.len = ee.value.count
                ee.tp = proc.name
                ee.data = proc.pack(nsline, m)
                return ee
            }
        }
    }

    /// Parse optionally marked-up text into structured representation.
    ///
    /// - Parameters:
    ///     - content: plain-text content to parse.
    /// - Returns: Drafty object.
    public static func parse(content: String) -> Drafty {
        // Break input into individual lines because format cannot span multiple lines.
        // This breaks lines by \n only, we do not expect to see Windows-style \r\n.
        let lines = content.components(separatedBy: .newlines)
        // This method also accounts for Windows-style line breaks, but it's probably not needed.
        // let lines = content.split { $0 == "\n" || $0 == "\r\n" }.map(String.init)
        var blks: [Block] = []
        var refs: [Entity] = []

        var entityMap: [String: JSONValue] = [:]
        for line in lines {
            var spans = Drafty.kInlineStyles.flatMap { (arg) -> [Span] in
                let (name, re) = arg
                return spannify(original: line, re: re, type: name)
            }

            let b: Block?
            if !spans.isEmpty {
                // Sort styled spans in ascending order by .start
                spans.sort { lhs, rhs in
                    return lhs.start < rhs.start
                }

                // Rearrange flat list of styled spans into a tree, throw away invalid spans.
                spans = toTree(spans: spans)

                // Parse the entire string into spans, styled or unstyled.
                spans = chunkify(line: line, start: 0, end: line.count, spans: spans)

                // Convert line into a block.
                b = draftify(chunks: spans, startAt: 0)
            } else {
                b = Block(txt: line)
            }

            if let b = b {
                // Extract entities from the string already cleared of markup.
                let eentities = extractEntities(line: b.txt)
                // Normalize entities by splitting them into spans and references.
                for eent in eentities {
                    // Check if the entity has been indexed already
                    var index = entityMap[eent.value]
                    if index == nil {
                        entityMap[eent.value] = JSONValue.int(refs.count)
                        index = entityMap[eent.value]
                        refs.append(Entity(tp: eent.tp, data: eent.data))
                    }

                    b.addStyle(s: Style(at: eent.at, len: eent.len, key: index!.asInt()))
                }

                blks.append(b)
            }
        }

        var text: String = ""
        var fmt: [Style] = []
        // Merge lines and save line breaks as BR inline formatting.
        if !blks.isEmpty {
            var b = blks[0]
            text = b.txt
            if let bfmt = b.fmt {
                fmt.append(contentsOf: bfmt)
            }
            for i in 1..<blks.count {
                let offset = text.count + 1
                fmt.append(Style(tp: "BR", at: offset - 1, len: 1))

                b = blks[i]
                text.append(" ") // BR points to this space
                text.append(b.txt)
                if let bfmt = b.fmt {
                    for s in bfmt {
                        s.at += offset
                        fmt.append(s)
                    }
                }
            }
        }

        return Drafty(text: text, fmt: fmt.isEmpty ? nil : fmt, ent: refs.isEmpty ? nil : refs)
    }

    /// Get inline styles and references to entities
    public var styles: [Style]? {
        return fmt
    }

    // Get entities (attachments)
    public var entities: [Entity]? {
        return ent
    }

    /// Extract attachment references for use in message header.
    ///
    /// - Returns: string array of attachment references or nil if no attachments with references were found.
    public func getEntReferences() -> [String]? {
        guard let ent = ent else { return nil }

        var result: [String] = []
        for anEnt in ent {
            if let ref = anEnt.data?["ref"] {
                switch ref {
                case .string(let str):
                    result.append(str)
                default: break
                }
            }
        }
        return result.isEmpty ? nil : result
    }

    /// Find entity from the reference given in style object
    public func entityFor(for style: Style) -> Entity? {
        let index = style.key ?? 0
        guard let ent = ent, ent.count > index else { return nil }
        return ent[index]
    }

    /// Convert Drafty to plain text
    public var string: String {
        return txt
    }

    /// Make sure Drafty is properly initialized for entity insertion.
    private func prepareForEntity(at: Int, len: Int) {
        if fmt == nil {
            fmt = []
        }
        if ent == nil {
            ent = []
        }
        fmt!.append(Style(at: at, len: len, key: ent!.count))
    }

    /// Make sure Drafty is properly initialized for style insertion.
    private func prepareForStyle() {
        if fmt == nil {
            fmt = []
        }
    }

    /// Insert inline image
    ///
    /// - Parameters:
    ///     - at: location to insert image at
    ///     - mime: Content-type, such as 'image/jpeg'.
    ///     - bits: Content as an array of bytes
    ///     - width: image width in pixels
    ///     - height: image height in pixels
    ///     - fname: name of the file to suggest to the receiver.
    /// - Returns: 'self' Drafty object.
    public func insertImage(at: Int, mime: String?, bits: Data, width: Int, height: Int, fname: String?) -> Drafty {
        return try! insertImage(at: at, mime: mime, bits: bits, width: width, height: height, fname: fname, refurl: nil, size: bits.count)
    }

    /// Insert image either as a reference or inline.
    ///
    /// - Parameters:
    ///     - at: location to insert image at
    ///     - mime: Content-type, such as 'image/jpeg'.
    ///     - bits: Content as an array of bytes
    ///     - width: image width in pixels
    ///     - height: image height in pixels
    ///     - fname: name of the file to suggest to the receiver.
    ///     - refurl: Reference to full/extended image.
    ///     - size: file size hint (in bytes) as reported by the client.
    /// - Returns: 'self' Drafty object.
    public func insertImage(at: Int, mime: String?, bits: Data?, width: Int, height: Int, fname: String?, refurl: URL?, size: Int) throws -> Drafty {
        guard bits != nil || refurl != nil else {
            throw DraftyError.illegalArgument("Either image bits or reference URL must not be null.")
        }

        guard txt.count > at && at >= 0 else {
            throw DraftyError.invalidIndex("Invalid insertion position")
        }

        prepareForEntity(at: at, len: 1)

        var data: [String: JSONValue] = [:]
        if let mime = mime, !mime.isEmpty {
            data["mime"] = JSONValue.string(mime)
        }
        if let bits = bits {
            data["val"] = JSONValue.bytes(bits)
        }
        data["width"] = JSONValue.int(width)
        data["height"] = JSONValue.int(height)
        if let fname = fname, !fname.isEmpty {
            data["name"] = JSONValue.string(fname)
        }
        if let refurl = refurl {
            data["ref"] = JSONValue.string(refurl.absoluteString)
        }
        if size > 0 {
            data["size"] = JSONValue.int(size)
        }
        ent!.append(Entity(tp: "IM", data: data))

        return self
    }

    /// Attach file to a drafty object inline.
    ///
    /// - Parameters:
    ///     - mime: Content-type, such as 'text/plain'.
    ///     - bits: Content as an array of bytes.
    ///     - fname: Optional file name to suggest to the receiver.
    /// - Returns: 'self' Drafty object.
    public func attachFile(mime: String?, bits: Data, fname: String?) -> Drafty {
        return try! attachFile(mime: mime, bits: bits, fname: fname, refurl: nil, size: bits.count)
    }

    /// Attach file to a drafty object as reference.
    ///
    /// - Parameters:
    ///     - mime: Content-type, such as 'text/plain'.
    ///     - fname: Optional file name to suggest to the receiver.
    ///     - refurl: reference to content location. If URL is relative, assume current server.
    ///     - size: size of the attachment (treated by client as an untrusted hint).
    /// - Returns: 'self' Drafty object.
    public func attachFile(mime: String?, fname: String?, refurl: URL, size: Int) throws -> Drafty {
        return try! attachFile(mime: mime, bits: nil, fname: fname, refurl: refurl, size: size)
    }

    /// Attach file to a drafty object either as a reference or inline.
    ///
    /// - Parameters:
    ///     - mime: Content-type, such as 'text/plain'.
    ///     - fname: Optional file name to suggest to the receiver.
    ///     - bits: Content as an array of bytes.
    ///     - refurl: reference to content location. If URL is relative, assume current server.
    ///     - size: size of the attachment (treated by client as an untrusted hint).
    /// - Returns: 'self' Drafty object.
    public func attachFile(mime: String?, bits: Data?, fname: String?, refurl: URL?, size: Int) throws -> Drafty {
        guard bits != nil || refurl != nil else {
            throw DraftyError.illegalArgument("Either file bits or reference URL must not be nil.")
        }

        prepareForEntity(at: -1, len: 1)

        var data: [String: JSONValue] = [:]
        if let mime = mime, !mime.isEmpty {
            data["mime"] = JSONValue.string(mime)
        }
        if let bits = bits {
            data["val"] = JSONValue.bytes(bits)
        }
        if let fname = fname, !fname.isEmpty {
            data["name"] = JSONValue.string(fname)
        }
        if let refurl = refurl {
            data["ref"] = JSONValue.string(refurl.absoluteString)
        }
        if size > 0 {
            data["size"] = JSONValue.int(size)
        }
        ent!.append(Entity(tp: "EX", data: data))

        return self
    }

    /// Attach object as json. Intended to be used as a form response.
    ///
    /// - Parameters:
    ///     - json: object to attach.
    /// - Returns: 'self' Drafty object.
    public func attachJSON(_ json: [String: JSONValue]) -> Drafty {
        prepareForEntity(at: -1, len: 1)

        var data: [String: JSONValue] = [:]
        data["mime"] = JSONValue.string(Drafty.kJSONMimeType)
        data["val"] = JSONValue.dict(json)
        ent!.append(Entity(tp: "EX", data: data))

        return self
    }

    /// Create a Drafty document consisting of a single mention.
    ///
    /// - Parameters:
    ///     - name: name of the user to be mentioned
    ///     - uid: user's unique id
    /// - Returns: new Drafty object mentioning the user.
    public static func mention(userWithName name: String, uid: String) -> Drafty {
        let d = Drafty(plainText: name)
        d.fmt = [Style(at: 0, len: name.count, key: 0)]
        d.ent = [Entity(tp: "MN", data: ["val": JSONValue.string(uid)])]
        return d
    }

    /// Wrap contents of the document into the specified style.
    ///
    /// - Parameters:
    ///     - style: style to wrap document into.
    /// - Returns: 'self' Drafty document wrapped in style.
    public func wrapInto(style: String) -> Drafty {
        prepareForStyle()
        fmt!.append(Style(tp: style, at: 0, len: txt.count))
        return self
    }

    /// Create a quote of a given Drafty document.
    ///
    /// - Parameters:
    ///     - header: Quote header (title, etc.).
    ///     - uid: UID of the author to mention.
    ///     - body: Body of the quoted message.
    /// - Returns:a Drafty doc with the quote formatting.
    public static func quote(quoteHeader header: String, authorUid uid: String, quoteContent body: Drafty) -> Drafty {
        return Drafty.mention(userWithName: header, uid: uid)
                .appendLineBreak()
                .append(body)
                .wrapInto(style: "QQ")
    }

    /// Append line break 'BR' to Darfty document
    /// - Returns: 'self' Drafty object.
    public func appendLineBreak() -> Drafty {
        prepareForStyle()
        fmt!.append(Style(tp: "BR", at: txt.count, len: 1))
        txt += " "
        return self
    }

    /// Append one Drafty document to another.
    /// - Returns: 'self' Drafty object.
    public func append(_ that: Drafty) -> Drafty {
        let len = txt.count
        txt += that.txt

        if let thatFmt = that.fmt {
            if fmt == nil {
                fmt = []
            }

            if that.ent != nil && ent == nil {
                ent = []
            }

            for src in thatFmt {
                let style = Style()
                style.at = src.at + len
                style.len = src.len
                if src.tp != nil {
                    style.tp = src.tp
                } else if let thatEnt = that.ent {
                    style.key = ent!.count
                    ent!.append(thatEnt[src.key ?? 0])
                }
                fmt!.append(style)
            }
        }

        return self
    }

    /// Insert button into Drafty document.
    ///
    /// - Parameters:
    ///     - at: is location where the button is inserted.
    ///     - len: is the length of the text to be used as button title.
    ///     - name: is an opaque ID of the button. Client should just return it to the server when the button is clicked.
    ///     - actionType: is the type of the button, one of 'url' or 'pub'.
    ///     - actionValue: is the value associated with the action: 'url': URL, 'pub': optional data to add to response.
    ///     - refUrl: parameter required by URL buttons: url to go to on click.
    ///
    /// - Returns: 'self' Drafty object.
    internal func insertButton(at: Int, len: Int, name: String?, actionType: String, actionValue: String?, refUrl: URL?) throws -> Drafty {
        prepareForEntity(at: at, len: len)

        guard actionType == "url" || actionType == "pub" else {
            throw DraftyError.illegalArgument("Unknown action type \(actionType)")
        }
        guard actionType == "url" && refUrl != nil else {
            throw DraftyError.illegalArgument("URL required for URL buttons")
        }

        var data: [String: JSONValue] = [:]
        data["act"] = JSONValue.string(actionType)
        if let name = name, !name.isEmpty {
            data["name"] = JSONValue.string(name)
        }
        if let actionValue = actionValue, !actionValue.isEmpty {
            data["val"] = JSONValue.string(actionValue)
        }
        if actionType == "url" {
            data["ref"] = JSONValue.string(refUrl!.absoluteString)
        }

        ent!.append(Entity(tp: "BN", data: data))

        return self
    }

    // Comparator is needed for testing.
    public static func == (lhs: Drafty, rhs: Drafty) -> Bool {
        return lhs.txt == rhs.txt &&
            lhs.fmt == rhs.fmt &&
            ((lhs.ent == nil && rhs.ent == nil) || (lhs.ent == rhs.ent))
    }

    /// Check if the instance contains no markup and consequently can be represented by
    /// plain String without loss of information.
    public var isPlain: Bool {
        return ent == nil && fmt == nil
    }

    /// Turns a Drafty object into a tree of spans and traverses it.
    /// Each node of the tree is processed using the provided context object.
    fileprivate class SpanTreeProcessor<TreeRoot: DraftySpan, Ctx> {
        // Inverse of chunkify. Returns a tree of formatted spans.
        func forEach(line: String, start startAt: Int, end: Int, spans: [Span], using context: Ctx) -> TreeRoot {
            let result = TreeRoot()

            var start = startAt
            guard !spans.isEmpty else {
                let content = String(line[line.index(line.startIndex, offsetBy: start)..<line.index(line.startIndex, offsetBy: end)])
                if let item = self.handleText(content, using: context) {
                    result.append(item)
                }
                return result
            }

            // Process ranges calling formatter for each range. Have to use index because it needs to step back.
            var i = 0
            while i < spans.count {
                let span = spans[i]
                i += 1
                if span.start < 0 && span.type == "EX" {
                    if let item = self.handleStyle(tp: span.type, attr: span.data, key: span.key, using: context) {
                        result.append(item)
                    }
                    continue
                }

                // Add un-styled range before the styled span starts.
                if start < span.start {
                    if let item = self.handleText(String(line[line.index(line.startIndex, offsetBy: start)..<line.index(line.startIndex, offsetBy: span.start)]), using: context) {
                        result.append(item)
                    }
                    start = span.start
                }

                // Get all spans which are within the current span.
                var subspans: [Drafty.Span] = []
                while i < spans.count {
                    let inner = spans[i]
                    i += 1
                    if inner.start >= 0 && inner.start < span.end {
                        subspans.append(inner)
                    } else {
                        // Move back.
                        i -= 1
                        break
                    }
                }

                if let item = self.handleSubspans(current: span, line: line, start: start, end: span.end, subspans: subspans, using: context) {
                    result.append(item)
                }

                start = span.end
            }

            // Add the last unformatted range.
            if start < end {
                if let item = self.handleText(String(line[line.index(line.startIndex, offsetBy: start)..<line.index(line.startIndex, offsetBy: end)]), using: context) {
                    result.append(item)
                }
            }

            return result
        }
        func handleText(_ content: String?, using context: Ctx) -> DraftySpan? {
            return nil
        }
        func handleStyle(tp: String?, attr: [String: JSONValue]?, key: Int?, using context: Ctx) -> DraftySpan? {
            return nil
        }
        func handleSubspans(current span: Span, line: String, start: Int, end: Int, subspans: [Span]?, using context: Ctx) -> DraftySpan? {
            return nil
        }
        func finalize(tree: TreeRoot, using context: Ctx) -> DraftySpan? {
            return nil
        }
        public func process(contentOf content: Drafty, using context: Ctx) -> DraftySpan? {
            // Handle special case when all values in fmt are 0 and fmt therefore was
            // skipped.
            let txt = content.txt
            var fmt = content.fmt
            let ent = content.ent
            if fmt == nil || fmt!.isEmpty {
                if ent != nil && ent!.count == 1 {
                    fmt = [Style(at: 0, len: 0, key: 0)]
                } else {
                    return self.handleText(txt, using: context)
                }
            }

            var attachments: [Span] = []
            var spans: [Span] = []
            let maxIndex = txt.count
            for aFmt in fmt! {
                if aFmt.len < 0 {
                    // Invalid length
                    continue
                }
                if aFmt.at < 0 {
                    // Attachment
                    aFmt.at = -1
                    aFmt.len = 1
                    let key = aFmt.key ?? 0
                    if key >= 0 {
                        attachments.append(Span(start: aFmt.at, end: 0, index: key))
                    }
                    continue
                } else if aFmt.at + aFmt.len > maxIndex {
                    // Out of bounds span.
                    continue
                }
                if aFmt.tp == nil || aFmt.tp!.isEmpty {
                    spans.append(Drafty.Span(start: aFmt.at, end: aFmt.at + aFmt.len, index: aFmt.key ?? 0))
                } else {
                    spans.append(Drafty.Span(type: aFmt.tp, start: aFmt.at, end: aFmt.at + aFmt.len))
                }
            }

            // Sort spans first by start index (asc) then by length (desc).
            spans.sort { lhs, rhs in
                if lhs.start == rhs.start {
                    return rhs.end < lhs.end // longer one comes first (<0)
                }
                return lhs.start < rhs.start
            }

            if !attachments.isEmpty {
                spans += attachments
            }

            for span in spans {
                if ent != nil && (span.type == nil || span.type!.isEmpty) {
                    if span.key >= 0 && span.key < ent!.count {
                        span.type = ent![span.key].tp
                        span.data = ent![span.key].data
                    }
                }

                // Is type still undefined? Hide the invalid element!
                if span.type == nil || span.type!.isEmpty {
                    span.type = "HD"
                }
            }
            let tree = self.forEach(line: txt, start: 0, end: txt.count, spans: spans, using: context)
            return self.finalize(tree: tree, using: context)
        }
    }

    class FormattingSpan: DraftySpan {
        var children: [DraftySpan]
        required init() {
            children = [DraftySpan]()
        }
        func append(_ newElement: DraftySpan) {
            children.append(newElement)
        }
    }

    fileprivate class FormattingProcessor: SpanTreeProcessor<FormattingSpan, DraftyFormatter> {
        let styleFormatters: [String: DraftyFormatter]?
        init(with customizers: [String: DraftyFormatter]?) {
            self.styleFormatters = customizers
        }
        override func handleText(_ content: String?, using formatter: DraftyFormatter) -> DraftySpan? {
            return formatter.apply(tp: nil, attr: nil, content: content)
        }
        override func handleStyle(tp: String?, attr: [String : JSONValue]?, key: Int?, using formatter: DraftyFormatter) -> DraftySpan? {
            return formatter.apply(tp: tp, attr: attr, content: nil)
        }
        override func finalize(tree: FormattingSpan, using formatter: DraftyFormatter) -> DraftySpan? {
            return formatter.apply(tp: nil, attr: nil, content: tree.children)
        }
        override func handleSubspans(current span: Span, line: String, start: Int, end: Int, subspans: [Drafty.Span]?, using defaultFormatter: DraftyFormatter) -> DraftySpan? {
            if span.type == "BN" {
                // Make button content unstyled.
                span.data = span.data ?? [:]
                let title = String(line[line.index(line.startIndex, offsetBy: span.start)..<line.index(line.startIndex, offsetBy: span.end)])
                span.data!["title"] = JSONValue.string(title)
                return defaultFormatter.apply(tp: span.type, attr: span.data, content: title)
            } else {
                var formatter: DraftyFormatter? = nil
                if let style = span.type, let customizer = self.styleFormatters?[style] {
                    formatter = customizer
                } else {
                    formatter = defaultFormatter
                }
                let tree = forEach(line: line, start: start, end: span.end, spans: subspans!, using: formatter!)
                return defaultFormatter.apply(tp: span.type, attr: span.data, content: tree.children)
            }
        }
    }

    /// Format converts Drafty object into a collection of nodes with format definitions.
    /// Each node contains either a formatted element or a collection of formatted elements.
    ///
    /// - Parameters:
    ///     - formatter: an interface with an `apply` methods. It's iteratively for to every node in the tree.
    /// - Returns: a tree of nodes.
    public func format(formatWith defaultFormatter: DraftyFormatter, customizeWith styleFormatters: [String: DraftyFormatter]? = nil) -> DraftySpan {
        let proc = FormattingProcessor(with: styleFormatters)
        return proc.process(contentOf: self, using: defaultFormatter)!
    }

    /// Creates a shortened and trimmed preview of the Drafty object.
    ///
    /// - Parameters:
    ///     - previewLen: maximum length of the preview.
    /// - Returns: a new Drafty object - a preview of the original object (self).
    public func preview(previewLen: Int) -> Drafty {
        let preview = preview(ofMaxLength: previewLen, using: PreviewTransformer())
        return preview!
    }

    //
    open class PreviewTransformer: SpanTreeTransformer {
        public init() {}
        open func transform(node: Span) -> Span? {
            //let node = node as! Span
            guard node.type != "QQ" else {
                return nil
            }
            guard node.type != "BR" else { return Span(text: " ")}
            guard let attr = node.data, !attr.isEmpty else { return node }

            var dc = [String: JSONValue]()
            for key in Entity.kLightData {
                if let val = attr[key] {
                    dc[key] = val
                }
            }

            let result = Span(from: node)
            if !dc.isEmpty {
                result.data = dc
            }
            return result
        }
    }

    fileprivate class PreviewProcessor<T: SpanTreeTransformer>: SpanTreeProcessor<Span, T> {
        override func handleText(_ content: String?, using transformer: T) -> DraftySpan? {
            guard  let txt = content else { return nil }
            let node = Span(text: txt)
            return transformer.transform(node: node)
        }
        override func handleStyle(tp: String?, attr: [String : JSONValue]?, key: Int?, using transformer: T) -> DraftySpan? {
            let node = Span(type: tp, data: attr, key: key ?? -1)
            return transformer.transform(node: node)
        }
        override func handleSubspans(current span: Span, line: String, start: Int, end: Int, subspans: [Span]?, using transformer: T) -> DraftySpan? {
            let node = forEach(line: line, start: start, end: end, spans: subspans!, using: transformer)
            let result = Span(type: span.type, data: span.data, key: span.key)
            result.append(node)
            return transformer.transform(node: result)
        }
        override func finalize(tree: Span, using transformer: T) -> DraftySpan? {
            return tree
        }
    }

    /// Creates a shortened and trimmed preview of the Drafty object.
    ///
    /// - Parameters:
    ///     - length: maximum length of the preview.
    ///     - transformer: defines how the nodes of the span tree of the given Drafty object should be modified
    /// - Returns: a new Drafty object - a preview of the original object (self).
    public func preview<T: SpanTreeTransformer>(ofMaxLength length: Int, using tranformer: T) -> Drafty? {
        let proc = PreviewProcessor<T>()
        let tree = proc.process(contentOf: self, using: tranformer) as! Span
        tree.clip(upToMax: length)
        // Remove leading whitespaces.
        tree.lTrim()
        var result = Drafty()
        var keymap = [Int: Int]()
        tree.appendTo(document: &result, using: &keymap)
        // Make attachments trailing.
        result.fmt?.forEach {
            if $0.at < 0 {
                $0.at = result.txt.count
                $0.len = 1
                result.txt.append(" ")
            }
        }
        return result
    }

    /// Serialize Drafty object for storage in database.
    public func serialize() -> String? {
        return isPlain ? txt : Tinode.serializeObject(self)
    }

    /// Deserialize Drafty object from database storage.
    public static func deserialize(from data: String?) -> Drafty? {
        guard let data = data else { return nil }
        if let drafty: Drafty = Tinode.deserializeObject(from: data) {
            return drafty
        }
        // Don't use init(content: data): there is no need to parse content again.
        return Drafty(text: data, fmt: nil, ent: nil)
    }

    /// Represents Drafty as JSON-like string.
    public var description: String {
        return "{txt: \"\(txt)\", fmt:\(fmt ?? []), ent:\(ent ?? [])}"
    }

    // MARK: Internal classes

    fileprivate class Block {
        var txt: String
        var fmt: [Style]?

        init(txt: String) {
            self.txt = txt
        }

        func addStyle(s: Style) {
            if fmt == nil {
                fmt = []
            }
            fmt!.append(s)
        }
    }

    public class Span: DraftySpan {
        public var start: Int
        public var end: Int
        public var key: Int
        public var text: String?
        public var type: String?
        public var data: [String: JSONValue]?
        public var children: [Span]?

        required public init() {
            start = 0
            end = 0
            key = 0
        }

        convenience init(text: String) {
            self.init()
            self.text = text
        }

        // Inline style
        convenience init(type: String?, start: Int, end: Int) {
            self.init()
            self.type = type
            self.start = start
            self.end = end
        }

        // Entity reference
        init(start: Int, end: Int, index: Int) {
            self.type = nil
            self.start = start
            self.end = end
            self.key = index
        }

        public convenience init(from another: Span) {
            self.init(start: another.start, end: another.end, index: another.key)
            self.children = another.children
            self.type = another.type
            self.data = another.data
            self.text = another.text
        }

        convenience init(type: String?, data: [String: JSONValue]?, key: Int) {
            self.init()
            self.type = type
            self.data = data
            self.key = key
        }

        public func append(_ child: DraftySpan) {
            if children == nil { children = [] }
            children!.append(child as! Span)
        }
        // Returns new length. If length is unchanged then it's returned
        // as a non-negative number. If changed then it's a negative number.
        @discardableResult
        func clip(upToMax budgetLength: Int) -> Int {
            if let txt = text {
                let len = txt.count
                if len > budgetLength {
                    text = String(txt[txt.index(txt.startIndex, offsetBy: 0)..<txt.index(txt.startIndex, offsetBy: budgetLength)])
                }
                return len > budgetLength ? budgetLength - len : len
            }
            // Children.
            guard let subtree = self.children else { return 0 }
            var accumulatedLen = 0
            var nodesProcessed = 0
            for child in subtree {
                let clen = child.clip(upToMax: budgetLength - accumulatedLen)
                nodesProcessed += 1
                guard clen >= 0 else {
                    self.children = subtree.dropLast(subtree.count - nodesProcessed)
                    return clen - accumulatedLen
                }
                accumulatedLen += clen
            }
            return accumulatedLen
        }
        // Removes spaces and breaks on the left. Returns true if the tree has been trimmed.
        @discardableResult
        func lTrim() -> Bool {
            if self.type == "BR" {
                text = nil
                type = nil
                children = nil
                return true
            }
            if let tp = self.type, !tp.isEmpty {
                // Explicit formatting. Skip.
                return false
            }
            if text != nil {
                let trimmed = self.text!.removingLeadingSpaces()
                if trimmed != self.text! {
                    self.text = trimmed
                    return true
                }
                return false
            } else {
                var result = false
                while (self.children?.first?.lTrim() ?? false) {
                    result = true
                }
                return result
            }
        }
        // Appends the tree of Spans (for which the root is self) to a Drafty doc.
        func appendTo(document doc: inout Drafty, using keymap: inout [Int: Int]) {
            let start = doc.length
            if let txt = text {
                doc.txt += txt
            } else if let children = self.children {
                for child in children {
                    child.appendTo(document: &doc, using: &keymap)
                }
            }
            if let tp = self.type {
                let addedLen = doc.length - start
                if addedLen == 0 && !(tp == "BR" || tp == "EX") {
                    return
                }
                if doc.fmt == nil { doc.fmt = [] }
                if let attr = self.data, !attr.isEmpty {
                    // Got entity.
                    if doc.ent == nil { doc.ent = [] }
                    var newKey: Int
                    if let oldKey = keymap[self.key] {
                        newKey = oldKey
                    } else {
                        newKey = doc.entities!.count
                        keymap[self.key] = newKey
                        doc.ent!.append(Entity(tp: tp, data: attr))
                    }
                    var at = -1
                    var len = 0
                    if tp != "EX" {
                        at = start
                        len = addedLen
                    }
                    doc.fmt!.append(Style(at: at, len: len, key: newKey))
                } else {
                    // No entity.
                    doc.fmt!.append(Style(tp: tp, at: start, len: addedLen))
                }
            }
        }
    }

    fileprivate class ExtractedEnt {
        var at: Int
        var len: Int
        var tp: String
        var value: String

        var data: [String: JSONValue]

        init() {
            at = 0
            len = 0
            tp = ""
            value = ""
            data = [:]
        }
    }
}

/// Representation of inline styles or entity references.
public class Style: Codable, CustomStringConvertible, Equatable {
    var at: Int
    var len: Int
    var tp: String?
    var key: Int?

    private enum CodingKeys: String, CodingKey {
        case at = "at"
        case len = "len"
        case tp = "tp"
        case key = "key"
    }

    /// Initializer to comply with Decodable protocol.
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = (try? container.decode(Int.self, forKey: .at)) ?? 0
        len = (try? container.decode(Int.self, forKey: .len)) ?? 0
        tp = try? container.decode(String.self, forKey: .tp)
        key = try? container.decode(Int.self, forKey: .key)
    }

    /// Initialize a zero-length unstyled object
    public init() {
        at = 0
        len = 0
    }

    /// Basic inline formatting
    /// - Parameters:
    ///     - tp: type of format
    ///     - at: starting index to apply the format from
    ///     - len: length of the formatting span
    public init(tp: String?, at: Int?, len: Int?) {
        self.at = at ?? 0
        self.len = len ?? 0
        self.tp = tp
        self.key = nil
    }

    /// Initialize with an entity reference
    /// - Parameters:
    ///     - at: index to insert entity at
    ///     - len: length of the span to cover with the entity
    ///     - Index of the entity in the entity container.
    public init(at: Int?, len: Int?, key: Int?) {
        self.tp = nil
        self.at = at ?? 0
        self.len = len ?? 0
        self.key = key
    }

    /// Styles are the same if they are the same type, start at the same location,
    /// have the same length and key
    public static func == (lhs: Style, rhs: Style) -> Bool {
        return lhs.tp == rhs.tp && lhs.at == rhs.at && lhs.at == rhs.at && lhs.key == rhs.key
    }

    /// Represents Style as JSON-like string.
    public var description: String {
        return "{tp: \(tp ?? "nil"), at: \(at), len:\(len), key:\(key ?? 0)}"
    }
}

/// Entity: style with additional data.
public class Entity: Codable, CustomStringConvertible, Equatable {
    fileprivate static let kLightData = ["mime", "name", "width", "height", "size"]
    public var tp: String?
    public var data: [String: JSONValue]?

    private enum CodingKeys: String, CodingKey {
        case tp = "tp"
        case data = "data"
    }

    /// Initializer to comply with Decodable protocol.
    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tp = try? container.decode(String.self, forKey: .tp)
        data = try? container.decode([String: JSONValue].self, forKey: .data)

        if tp != "MN" {
            // data["val"] is expected to be a large base64-encoded string. Decode it to Data so it does not need to decoded it every time it's accessed
            if let val = data?["val"]?.asString() {
                if let bits = Data(base64Encoded: val, options: .ignoreUnknownCharacters) {
                    data!["val"] = JSONValue.bytes(bits)
                } else {
                    // If the data cannot be decoded then it's useless
                    data!["val"] = nil
                }
            }
        }
    }

    /// Initialize an empty attachment.
    public init() {}

    /// Initialize an entity with type and payload
    /// - Parameters:
    ///     - tp: type of attachment
    ///     - data: payload
    public init(tp: String?, data: [String: JSONValue]?) {
        self.tp = tp
        self.data = data
    }

    public static func == (lhs: Entity, rhs: Entity) -> Bool {
        return lhs.tp == rhs.tp && ((lhs.data ?? [:]) == (rhs.data ?? [:]))
    }

    /// Represents Style as JSON-like string.
    public var description: String {
        return "{tp: \(tp ?? "nil"), data: \(data ?? [:])}"
    }

    /// Returns a copy of the original entity with the data restricted to the kLightData array keys.
    public func copyLight() -> Entity {
        var dataCopy: [String: JSONValue]?
        if let dt = self.data, !dt.isEmpty {
            var dc: [String: JSONValue] = [:]
            for key in Entity.kLightData {
                if let val = dt[key] {
                    dc[key] = val
                }
            }
            if !dc.isEmpty {
                dataCopy = dc
            }
        }
        return Entity(tp: self.tp, data: dataCopy)
    }
}

private class EntityProc {
    var name: String
    var re: NSRegularExpression
    var pack: (_ text: NSString, _ m: NSTextCheckingResult) -> [String: JSONValue]

    init(name: String, pattern: NSRegularExpression, pack: @escaping (_ text: NSString, _ m: NSTextCheckingResult) -> [String: JSONValue]) {
        self.name = name
        self.re = pattern
        self.pack = pack
    }
}

extension String {
    // Trims whitespaces and new lines on the left.
    func removingLeadingSpaces() -> String {
        guard let index = firstIndex(where: { !CharacterSet(charactersIn: String($0)).isSubset(of: .whitespacesAndNewlines) }) else {
            // No such index (i.e. all characters are whitespace chars)? - Trim all.
            return ""
        }
        return String(self[index...])
    }
}
