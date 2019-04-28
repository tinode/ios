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

    func testExample() {
        var text = Drafty("abc")
        text.append("d")
        XCTAssertEqual(text, "abcd", "Appending a 'd' to \"abc\" should produce \"abcd\"")
    }

    func testPerformanceExample() {
        self.measure {
            for i in 0..<10000 {
                var m = Drafty("abcd \(i)")
                let start = m.index(m.startIndex, offsetBy: 1)
                let end = m.index(m.startIndex, offsetBy: 3)
                m.replaceSubrange(start..<end, with: "!!")
            }
        }
    }

}
