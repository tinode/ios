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
        var d1 = Drafty("abc")
        var d2 = Drafty(text: "abc", fmt: nil, ent: nil)
        XCTAssertEqual(d1, d2, "Parsing 'abc' should produce '\(d2)'")

        d1 = Drafty("this is *bold*, `code` and _italic_, ~strike~")
        d2 = Drafty(text: "this is bold, code and italic, strike",
                    fmt: [Style(at:8, len:4,tp:"ST"),
                          Style(at:14, len:4, tp:"CO"),
                          Style(at:23, len:6, tp:"EM"),
                          Style(at:31, len:6, tp:"DL")], ent: [])
        XCTAssertEqual(d1, d2, "Parsing 'this is *bold*, `code` and _italic_, ~strike~' should produce '\(d2)', NOT '\(d1)'")
    }

    func testPerformanceParse() {
        self.measure {
            for i in 0..<10000 {
                var m = Drafty("*abcd _\(i)_*\nsecond line https://www.example.com/ @mention")
            }
        }
    }

}
