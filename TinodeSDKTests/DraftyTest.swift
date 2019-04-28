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
        XCTAssertEqual(d1, d2, "Parsing 'abc' should produce '\(d2)'")

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
                    fmt: [Style(tp:"ST", at:6, len:12),
                          Style(tp:"EM", at:9, len:6)], ent: nil)

        XCTAssertEqual(d1, d2, "Nested: 'start *b1 _italic_ b2* close'")
    }

    func testPerformanceParse() {
        self.measure {
            for i in 0..<10000 {
                var m = Drafty(content: "*abcd _\(i)_*\nsecond line https://www.example.com/ @mention")
            }
        }
    }

}
