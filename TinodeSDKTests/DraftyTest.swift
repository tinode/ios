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
        var d1 = Drafty(content: "abc")
        var d2 = Drafty(text: "abc", fmt: nil, ent: nil)
        XCTAssertEqual(d1, d2, "Basic: 'abc'")

        d1 = Drafty(content: "this is *bold*, `code` and _italic_, ~strike~")
        d2 = Drafty(text: "this is bold, code and italic, strike",
                    fmt: [Style(tp:"ST", at:8, len:4),
                          Style(tp:"CO", at:14, len:4),
                          Style(tp:"EM", at:23, len:6),
                          Style(tp:"DL", at:31, len:6)], ent: nil)
        XCTAssertEqual(d1, d2, "Serial: 'this is *bold*, `code` and _italic_, ~strike~'")

        d1 = Drafty(content: "line one\nline two")
        d2 = Drafty(text: "line one line two",
                    fmt: [Style(tp:"BR", at:8, len:1)], ent: nil)
        XCTAssertEqual(d1, d2, "Multiline: 'line one\\nline two'")

        d1 = Drafty(content: "start *b1 _italic_ b2* close")
        d2 = Drafty(text: "start b1 italic b2 close",
                    fmt: [Style(tp:"EM", at:9, len:6),
                          Style(tp:"ST", at:6, len:12)], ent: nil)
        XCTAssertEqual(d1, d2, "Nested: 'start *b1 _italic_ b2* close'")

        d1 = Drafty(content: "*bold _italic_*")
        d2 = Drafty(text: "bold italic",
                    fmt: [Style(tp:"EM", at:5, len:6),
                          Style(tp:"ST", at:0, len:11)], ent: nil)
        XCTAssertEqual(d1, d2, "Nested II: '*bold _italic_*'")

        d1 = Drafty(content: "_italic *bold*_")
        d2 = Drafty(text: "italic bold",
                    fmt: [Style(tp:"ST", at:7, len:4),
                          Style(tp:"EM", at:0, len:11)], ent: nil)
        XCTAssertEqual(d1, d2, "Nested III: '_italic *bold*_'")


        d1 = Drafty(content: "мама _мыла_ раму")
        d2 = Drafty(text: "мама мыла раму",
                    fmt: [Style(tp:"EM", at:5, len:4)], ent: nil)
        XCTAssertEqual(d1, d2, "Cyrillic: 'мама *мыла* раму'")

        d1 = Drafty(content: "😀 *b1👩🏽‍✈️b2* smile")
        d2 = Drafty(text: "😀 b1👩🏽‍✈️b2 smile",
                    fmt: [Style(tp:"ST", at:2, len:5)], ent: nil)
        XCTAssertEqual(d1, d2, "UTF32 emoji: '😀 b1👩🏽‍✈️b2 smile'")

    }

    func testPreview() {
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
        d2 = Drafty(text: " abc",
                    fmt: [Style(at: 0, len: 1, key: 0), Style(tp: "BR", at: 1, len: 1)],
                    ent: [Entity(tp: "IM", data: ["mime": JSONValue.string("image/jpeg"), "width": JSONValue.int(100), "height": JSONValue.int(100)])])
        XCTAssertEqual(d1, d2, "UTF32 emoji with entity: '<image> abcdef my image")
    }

    func testPerformanceParse() {
        self.measure {
            for i in 0..<10000 {
                Drafty(content: "*abcd _\(i)_*\nsecond line https://www.example.com/ @mention")
            }
        }
    }

}
