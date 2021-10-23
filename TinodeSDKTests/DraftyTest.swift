//
//  DraftyTest.swift
//  TinodeSDKTests
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import XCTest
@testable import TinodeSDK

class DraftyTest: XCTestCase {

    override func setUp() {
    }

    override func tearDown() {
    }

    func testParse() {
        // String 1: basic
        var d1 = Drafty(content: "abc")
        var d2 = Drafty(text: "abc", fmt: nil, ent: nil)
        XCTAssertEqual(d1, d2, "String 1 - Basic: 'abc'")

        // String 2: Basic formatting
        d1 = Drafty(content: "this is *bold*, `code` and _italic_, ~strike~")
        d2 = Drafty(text: "this is bold, code and italic, strike",
                    fmt: [Style(tp:"ST", at:8, len:4),
                          Style(tp:"CO", at:14, len:4),
                          Style(tp:"EM", at:23, len:6),
                          Style(tp:"DL", at:31, len:6)], ent: nil)
        XCTAssertEqual(d1, d2, "String 2 - Basic formatting: 'this is *bold*, `code` and _italic_, ~strike~'")

        // String 3: Basic formatting over Unicode
        d1 = Drafty(content: "Это *жЫрный*, `код` и _наклонный_, ~зачеркнутый~")
        d2 = Drafty(text: "Это жЫрный, код и наклонный, зачеркнутый",
                    fmt: [Style(tp:"ST", at:4, len:6),
                          Style(tp:"CO", at:12, len:3),
                          Style(tp:"EM", at:18, len:9),
                          Style(tp:"DL", at:29, len:11)], ent: nil)
        XCTAssertEqual(d1, d2, "String 3 - Basic formatting over Unicode: 'Это *жЫрный*, `код` и _наклонный_, ~зачеркнутый~'")

        // String 4: Multiline
        d1 = Drafty(content: "line one\nline two")
        d2 = Drafty(text: "line one line two",
                    fmt: [Style(tp:"BR", at:8, len:1)], ent: nil)
        XCTAssertEqual(d1, d2, "String 4 - Multiline: 'line one\\nline two'")

        // String 5: Nested formatting
        d1 = Drafty(content: "start *b1 _italic_ b2* close")
        d2 = Drafty(text: "start b1 italic b2 close",
                    fmt: [Style(tp:"EM", at:9, len:6),
                          Style(tp:"ST", at:6, len:12)], ent: nil)
        XCTAssertEqual(d1, d2, "String 5 - Nested formatting: 'start *b1 _italic_ b2* close'")

        // String 6: Nested formatting II
        d1 = Drafty(content: "*bold _italic_*")
        d2 = Drafty(text: "bold italic",
                    fmt: [Style(tp:"EM", at:5, len:6),
                          Style(tp:"ST", at:0, len:11)], ent: nil)
        XCTAssertEqual(d1, d2, "String 6 - Nested II: '*bold _italic_*'")

        // String 7: Nested formatting III
        d1 = Drafty(content: "_italic *bold*_")
        d2 = Drafty(text: "italic bold",
                    fmt: [Style(tp:"ST", at:7, len:4),
                          Style(tp:"EM", at:0, len:11)], ent: nil)
        XCTAssertEqual(d1, d2, "String 7 - Nested III: '_italic *bold*_'")

        // String 8: Unicode string II
        d1 = Drafty(content: "мама _мыла_ раму")
        d2 = Drafty(text: "мама мыла раму",
                    fmt: [Style(tp:"EM", at:5, len:4)], ent: nil)
        XCTAssertEqual(d1, d2, "String 8 - Unicode string II: 'мама *мыла* раму'")

        // String 9: Unicode III
        d1 = Drafty(content: "😀 *b1👩🏽‍✈️b2* smile")
        d2 = Drafty(text: "😀 b1👩🏽‍✈️b2 smile",
                    fmt: [Style(tp:"ST", at:2, len:5)], ent: nil)
        XCTAssertEqual(d1, d2, "String 8 - Unicode III UTF32 emoji: '😀 b1👩🏽‍✈️b2 smile'")

        // String 10: links
        d1 = Drafty(content: "an url: https://www.example.com/abc#fragment and another _www.tinode.co_")
        d2 = Drafty(text: "an url: https://www.example.com/abc#fragment and another www.tinode.co",
                    fmt: [Style(tp: "EM", at: 57, len: 13),
                          Style(at: 8, len: 36, key: 0),
                          Style(at: 57, len: 13, key: 1)],
                    ent: [Entity(tp: "LN", data: ["url": .string("https://www.example.com/abc#fragment")]),
                          Entity(tp: "LN", data: ["url": .string("http://www.tinode.co")])])
        XCTAssertEqual(d1, d2, "String 10 - links")

        // String 11: mention and hashtag
        d1 = Drafty(content: "this is a @mention and a #hashtag in a string");
        d2 = Drafty(text: "this is a @mention and a #hashtag in a string",
                    fmt: [Style(at: 10, len: 8, key: 0), Style(at: 25, len: 8, key: 1)],
                    ent: [Entity(tp: "MN", data: ["val": .string("mention")]),
                          Entity(tp: "HT", data: ["val": .string("hashtag")])])
        XCTAssertEqual(d1, d2, "String 11 - mention and hashtag")

        // String 12: hashtag Unicode
        d1 = Drafty(content: "second #юникод")
        d2 = Drafty(text: "second #юникод",
                    fmt: [Style(at: 7, len: 7, key: 0)],
                    ent: [Entity(tp: "HT", data: ["val": .string("юникод")])])
        XCTAssertEqual(d1, d2, "String 12 - hashtag Unicode")
    }

    func testPreview() {
        // Basic cases
        var d1 = Drafty(content: "abc").preview(previewLen: 2)
        var d2 = Drafty(text: "ab", fmt: nil, ent: nil)
        XCTAssertEqual(d1, d2, "Basic: 'abc' -> 'ab'")

        d1 = Drafty(content: "a😀c").preview(previewLen: 2)
        d2 = Drafty(text: "a😀", fmt: nil, ent: nil)
        XCTAssertEqual(d1, d2, "UTF32 emoji: 'a😀c' -> 'a😀'")

        d1 = Drafty(content: "_😀 *b1👩🏽‍✈️b2* smile_").preview(previewLen: 6)
        d2 = Drafty(text: "😀 b1👩🏽‍✈️b",
                    fmt: [Style(tp:"ST", at:2, len:5), Style(tp:"EM", at:0, len:13)], ent: nil)
        XCTAssertEqual(d1, d2, "UTF32 emoji with styles: '😀 b1👩🏽‍✈️b'")

        d1 = Drafty(text: " abcdef my image",
                    fmt: [Style(at: 0, len: 1, key: 0), Style(tp: "BR", at: 1, len: 1)],
                    ent: [Entity(tp: "IM", data: ["mime": JSONValue.string("image/jpeg"), "width": JSONValue.int(100), "height": JSONValue.int(100)])]).preview(previewLen: 4)
        d2 = Drafty(text: "  bc",
                    fmt: [Style(at: 0, len: 1, key: 0)/*, Style(tp: "BR", at: 1, len: 1)*/],
                    ent: [Entity(tp: "IM", data: ["mime": JSONValue.string("image/jpeg"), "width": JSONValue.int(100), "height": JSONValue.int(100)])])
        XCTAssertEqual(d1, d2, "UTF32 emoji with entity: '<image> abcdef my image")

        // ------- Preview 1
        d1 = Drafty(content: "This is a plain text string.").preview(previewLen: 15)
        d2 = Drafty(content: "This is a plain")
        XCTAssertEqual(d1, d2, "Preview 1 failed")

        // ------- Preview 2
        d1 = Drafty(
            text: "", fmt: [Style(at: -1, len: 0, key: 0)],
            ent: [Entity(tp: "EX",
                         data: ["mime": JSONValue.string("image/jpeg"),
                                "name": JSONValue.string("hello.jpg"),
                                "val": JSONValue.string("<38992, bytes: ...>"),
                                "width": JSONValue.int(100),
                                "height": JSONValue.int(80)])]).preview(previewLen: 15)
        d2 = Drafty(
            text: "", fmt: [Style(at: -1, len: 0, key: 0)],
            ent: [Entity(tp: "EX",
                         data: ["mime": JSONValue.string("image/jpeg"),
                                "name": JSONValue.string("hello.jpg"),
                                // "val" will be filtered out.
                                "width": JSONValue.int(100),
                                "height": JSONValue.int(80)])])
        XCTAssertEqual(d1, d2, "Preview 2 failed")

        // ------- Preview 3
        d1 = Drafty(text: "https://api.tinode.co/",
                    fmt: [Style(at: 0, len: 22, key: 0)],
                    ent: [Entity(tp: "LN", data: ["url": .string("https://www.youtube.com/watch?v=dQw4w9WgXcQ")])])
            .preview(previewLen: 15)
        d2 = Drafty(text: "https://api.tin",
                    fmt: [Style(at: 0, len: 15, key: 0)],
                    ent: [Entity(tp: "LN", data: ["url": .string("https://www.youtube.com/watch?v=dQw4w9WgXcQ")])])
        XCTAssertEqual(d1, d2, "Preview 3 failed")

        // ------- Preview 4 (two references to the same entity).
        d1 = Drafty(text: "Url one, two",
                    fmt: [Style(at: 9, len: 3, key: 0), Style(at: 4, len: 3, key: 0)],
                    ent: [Entity(tp: "LN", data: ["url": .string("http://tinode.co")])])
            .preview(previewLen: 15)
        d2 = Drafty(text: "Url one, two",
                    fmt: [Style(at: 4, len: 3, key: 0), Style(at: 9, len: 3, key: 0)],
                    ent: [Entity(tp: "LN", data: ["url": .string("http://tinode.co")])])
        XCTAssertEqual(d1, d2, "Preview 4 failed")

        // ------- Preview 5 (two different entities).
        d1 = Drafty(text: "Url one, two",
                    fmt: [Style(at: 9, len: 3, key: 1), Style(at: 4, len: 3, key: 0)],
                    ent: [Entity(tp: "LN", data: ["url": .string("http://tinode.co")]),
                          Entity(tp: "LN", data: ["url": .string("http://example.com")])])
            .preview(previewLen: 15)
        d2 = Drafty(text: "Url one, two",
                    fmt: [Style(at: 4, len: 3, key: 0), Style(at: 9, len: 3, key: 1)],
                    ent: [Entity(tp: "LN", data: ["url": .string("http://tinode.co")]),
                          Entity(tp: "LN", data: ["url": .string("http://example.com")])])
        XCTAssertEqual(d1, d2, "Preview 5 failed")

        // ------- Preview 6 (inline image)
        d1 = Drafty(text: " ",
                    fmt: [Style(at: 0, len: 1, key: 0)],
                    ent: [Entity(tp: "IM", data: [
                        "height": .int(213),
                        "width": .int(638),
                        "name": .string("roses.jpg"),
                        "val": .string("<38992, bytes: ...>"),
                        "mime": .string("image/jpeg")
                    ])])
            .preview(previewLen: 15)
        d2 = Drafty(text: " ",
                    fmt: [Style(at: 0, len: 1, key: 0)],
                    ent: [Entity(tp: "IM", data: [
                        "height": .int(213),
                        "width": .int(638),
                        "name": .string("roses.jpg"),
                        // "val" is filtered out.
                        "mime": .string("image/jpeg")
                    ])])
        XCTAssertEqual(d1, d2, "Preview 6 failed")

        /*
        TODO: enable.
        // ------- Preview 7 (staggered formats)
        d1 = Drafty(text: "This text has staggered formats",
                    fmt: [Style(tp: "EM", at: 5, len: 8), Style(tp: "ST", at: 10, len: 13)],
                    ent: nil)
        d1 = d1.preview(previewLen: 15)
        d2 = Drafty(text: "This text has s",
                    fmt: [Style(tp: "EM", at: 5, len: 8)],
                    ent: nil)
        XCTAssertEqual(d1, d2, "Preview 7 failed")
        */

        // ------- Preview 8 (multiple formatting)
        d1 = Drafty(text: "This text is formatted and deleted too",
                    fmt: [Style(tp: "ST", at: 5, len: 4),
                          Style(tp: "EM", at: 13, len: 9),
                          Style(tp: "ST", at: 35, len: 3),
                          Style(tp: "DL", at: 27, len: 11)],
                    ent: nil)
            .preview(previewLen: 15)
        d2 = Drafty(text: "This text is fo",
                    fmt: [Style(tp: "ST", at: 5, len: 4),
                          Style(tp: "EM", at: 13, len: 2)],
                    ent: nil)
        XCTAssertEqual(d1, d2, "Preview 8 failed")

        //  -------  Preview 9 (multibyte unicode)
        d1 = Drafty(text: "мультибайтовый юникод",
                    fmt: [Style(tp: "ST", at: 0, len: 14), Style(tp: "EM", at: 15, len: 6)], ent: nil)
            .preview(previewLen: 15)
        d2 = Drafty(text: "мультибайтовый ",
                    fmt: [Style(tp: "ST", at: 0, len: 14)], ent: nil)
        XCTAssertEqual(d1, d2, "Preview 9 failed")

        //  -------  Preview 10 (quoted reply)
        d1 = Drafty(text: "Alice Johnson    This is a test",
                    fmt: [Style(tp: "BR", at: 13, len: 1),
                          Style(at: 15, len: 1, key: 0),
                          Style(at: 0, len: 13, key: 1),
                          Style(tp: "QQ", at: 0, len: 16),
                          Style(tp: "BR", at: 16, len: 1)],
                    ent: [Entity(tp: "IM",
                                 data: ["mime": .string("image/jpeg"),
                                        "val": .string("<1292, bytes: /9j/4AAQSkZJ...rehH5o6D/9k=>"),
                                        "width": .int(25),
                                        "height": .int(14),
                                        "size": .int(968)]),
                          Entity(tp: "MN",
                                 data: ["val": .string("usr12345678")])])
            .preview(previewLen: 15)
        d2 = Drafty(content: "This is a test")
        XCTAssertEqual(d1, d2, "Preview 10 failed")
    }

    func testPerformanceParse() {
        self.measure {
            for i in 0..<10000 {
                Drafty(content: "*abcd _\(i)_*\nsecond line https://www.example.com/ @mention")
            }
        }
    }

}
