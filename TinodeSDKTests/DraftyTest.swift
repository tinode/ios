//
//  DraftyTest.swift
//  TinodeSDKTests
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
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

        // String 13: two lines with emoji in the first and style in the second.
        d1 = Drafty(content: "first 😀 line\nsecond *line*")
        d2 = Drafty(text: "first 😀 line second line",
                    fmt: [Style(tp: "BR", at: 12, len: 1), Style(tp: "ST", at: 20, len: 4)], ent: nil)
        XCTAssertEqual(d1, d2, "String 13 - two lines with emoji in the first and style in the second")

        // String 14: another compound Unicode test
        d1 = Drafty(content: "🔴Hello🔴\n🟠Hello🟠")
        d2 = Drafty(text: "🔴Hello🔴 🟠Hello🟠", fmt: [Style(tp: "BR", at: 7, len: 1)], ent: nil)
        XCTAssertEqual(d1, d2, "String 14 - two lines with compound emojis")
    }

    func testShorten() {
        let limit = 15

        // ------- Shorten 1
        var src = Drafty(plainText: "This is a plain text string.")
        var actual = src.shorten(previewLen: limit, stripHeavyEntities: true)
        var expected = Drafty(plainText: "This is a plai…")
        XCTAssertEqual(expected, actual, "Shorten 1 has failed")

        // ------- Shorten 2
        src = Drafty(
            text: "",
            fmt: [Style(at: -1, len: 0, key: 0)],
            ent: [Entity(tp: "EX",
                         data: [
                        "mime": .string("image/jpeg"),
                        "name": .string("hello.jpg"),
                        "val": .string("<38992, 123456789012345678901234567890123456789012345678901234567890 bytes: ...>"),
                        "width": .int(100),
                        "height": .int(80),
                     ])]
        )
        actual = src.shorten(previewLen: limit, stripHeavyEntities: true);
        expected = Drafty(text: "",
                          fmt: [Style(at: -1, len: 0, key: 0)],
                          ent: [Entity(tp: "EX", data: [
                            "mime": .string("image/jpeg"),
                            "name": .string("hello.jpg"),
                            "width": .int(100),
                            "height": .int(80),
        ])]
                          )
        XCTAssertEqual(expected, actual, "Shorten 2 has failed")

        // ------- Shorten 3
        src = Drafty(
            text: "https://api.tinode.co/",
            fmt: [Style(at: 0, len: 22, key: 0)],
            ent: [Entity(tp: "LN", data: ["url": .string("https://www.youtube.com/watch?v=dQw4w9WgXcQ")])]
        )
        actual = src.shorten(previewLen: limit, stripHeavyEntities: true);
        expected = Drafty(
            text: "https://api.ti…",
            fmt: [Style(at: 0, len: 15, key: 0)],
            ent: [Entity(tp: "LN", data: ["url": .string("https://www.youtube.com/watch?v=dQw4w9WgXcQ")])]
        )
        XCTAssertEqual(expected, actual, "Shorten 3 has failed");

        // ------- Shorten 4 (two references to the same entity).
        src = Drafty(
            text: "Url one, two",
            fmt: [Style(at: 9, len: 3, key: 0), Style(at: 4, len: 3, key: 0)],
            ent: [Entity(tp: "LN", data: ["url": .string("http://tinode.co")])]
        )
        actual = src.shorten(previewLen: limit, stripHeavyEntities: true);
        expected = Drafty(
            text: "Url one, two",
            fmt: [Style(at: 4, len: 3, key: 0), Style(at: 9, len: 3, key: 0)],
            ent: [Entity(tp: "LN", data: ["url": .string("http://tinode.co")])]
        )
        XCTAssertEqual(expected, actual, "Shorten 4 has failed");

        // ------- Shorten 5 (two different entities).
        src = Drafty(
            text: "Url one, two",
            fmt: [Style(at: 4, len: 3, key: 0), Style(at: 9, len: 3, key: 1)],
            ent: [
                Entity(tp: "LN", data: ["url": .string("http://tinode.co")]),
                Entity(tp: "LN", data: ["url": .string("http://example.com")])
            ]
        )
        actual = src.shorten(previewLen: limit, stripHeavyEntities: true);
        expected = Drafty(
            text: "Url one, two",
            fmt: [Style(at: 4, len: 3, key: 0), Style(at: 9, len: 3, key: 1)],
            ent: [
                Entity(tp: "LN", data: ["url": .string("http://tinode.co")]),
                Entity(tp: "LN", data: ["url": .string("http://example.com")]),
            ]
        )
        XCTAssertEqual(expected, actual, "Shorten 5 has failed");

        // ------- Shorten 6 (inline image)
        src = Drafty(
            text: " ",
            fmt: [Style(at: 0, len: 1, key: 0)],
            ent: [Entity(
                tp: "IM",
                data: [
                    "height": .int(213),
                    "width": .int(638),
                    "name": .string("roses.jpg"),
                    "val": .string("<38992, 123456789012345678901234567890123456789012345678901234567890 bytes: ...>"),
                    "mime":.string("image/jpeg")
                ])
            ]
        )
        actual = src.shorten(previewLen: limit, stripHeavyEntities: true);
        expected = Drafty(
            text: " ",
            fmt: [Style(at: 0, len: 1, key: 0)],
            ent: [Entity(
                tp: "IM",
                data: [
                    "height": .int(213),
                    "width": .int(638),
                    "name": .string("roses.jpg"),
                    "mime": .string("image/jpeg")
                ])
            ]
        )
        XCTAssertEqual(expected, actual, "Shorten 6 has failed");

        // ------- Shorten 7 (staggered formats)
        src = Drafty(
            text: "This text has staggered formats" ,
            fmt: [
                Style(tp: "EM", at: 5, len: 8),
                Style(tp: "ST", at: 10, len: 13)
            ],
            ent: nil
        )
        actual = src.shorten(previewLen: limit, stripHeavyEntities: true);
        expected = Drafty(
            text: "This text has …",
            fmt: [Style(tp: "EM", at: 5, len: 8)],
            ent: nil
        )
        XCTAssertEqual(expected, actual, "Shorten 7 has failed");

        // ------- Shorten 8 (multiple formatting)
        src = Drafty(
            text: "This text is formatted and deleted too" ,
            fmt: [
                Style(tp: "ST", at: 5, len: 4),
                Style(tp: "EM", at: 13, len: 9),
                Style(tp: "ST", at: 35, len: 3),
                Style(tp: "DL", at: 27, len: 11)
            ],
            ent: nil
        )

        actual = src.shorten(previewLen: limit, stripHeavyEntities: true);
        expected = Drafty(
            text: "This text is f…",
            fmt: [
                Style(tp: "ST", at: 5, len: 4),
                Style(tp: "EM", at: 13, len: 2),
            ],
            ent: nil
        )
        XCTAssertEqual(expected, actual, "Shorten 8 has failed");

        //  -------  Shorten 9 (multibyte unicode)
        src = Drafty(
            text: "мультибайтовый юникод",
            fmt: [
                Style(tp: "ST", at: 0, len: 14),
                Style(tp: "EM", at: 15, len: 6),
            ],
            ent: nil
        )
        actual = src.shorten(previewLen: limit, stripHeavyEntities: true);
        expected = Drafty(
            text: "мультибайтовый…",
            fmt: [Style(tp: "ST", at: 0, len: 14)],
            ent: nil
        )
        XCTAssertEqual(expected, actual, "Shorten 9 has failed");

        //  -------  Shorten 10 (quoted reply)
        src = Drafty(
            text: "Alice Johnson    This is a test",
            fmt: [
                Style(tp: "BR", at: 13,len: 1),
                Style(at: 15,len: 1, key: 0),
                Style(at: 0, len: 13, key: 1),
                Style(tp: "QQ", at: 0, len: 16),
                Style(tp: "BR", at: 16, len: 1)
            ],
            ent: [
                Entity(tp: "IM", data: [
                    "mime": .string("image/jpeg"),
                    "val": .string("<1292, bytes: /9j/4AAQSkZJ.123456789012345678901234567890123456789012345678901234567890.rehH5o6D/9k=>"),
                    "width": .int(25),
                    "height": .int(14),
                    "size": .int(968),
                ]),
                Entity(tp: "MN", data: ["val": .string("usr123abcDE")])
            ]
        )
        actual = src.shorten(previewLen: limit, stripHeavyEntities: true);

        expected = Drafty(
            text: "Alice Johnson …",
            fmt: [
                Style(at: 0, len: 13, key: 0),
                Style(tp: "BR", at: 13, len: 1),
                Style(tp: "QQ", at: 0, len: 15)
            ],
            ent: [Entity(tp: "MN", data: ["val": .string("usr123abcDE")])]
        )
        XCTAssertEqual(expected, actual, "Shorten 10 has failed");

        // Emoji 1
        src = Drafty(plainText: "a😀cd")
        actual = src.shorten(previewLen: 3, stripHeavyEntities: false)
        expected = Drafty(text: "a😀…", fmt: nil, ent: nil)
        XCTAssertEqual(expected, actual, "Shorten Emoji 1 has failed")

        // Emodji 2
        src = Drafty(content: "_😀 *b1👩🏽‍✈️b2* smile_")
        expected = src.shorten(previewLen: 6, stripHeavyEntities: false)
        actual = Drafty(
            text: "😀 b1👩🏽‍✈️…",
            fmt: [
                Style(tp:"ST", at:2, len:5),
                Style(tp:"EM", at:0, len:6)],
            ent: nil
        )
        XCTAssertEqual(expected, actual, "Shorten UTF32 emoji has failed")
    }

    func testForward() {
        // ------- Forward 1 (unchanged).
        var src = Drafty(
            text: "Alice Johnson This is a reply to replyThis is a Reply -> Forward -> Reply." ,
            fmt: [
                Style(at: 0, len: 13, key: 0),
                Style(tp: "BR", at: 13,len: 1),
                Style(tp: "QQ", at: 0, len: 38)
            ],
            ent: [Entity(tp: "MN", data: ["val": .string("usr123abcDE")])]
        )
        var actual = src.forwardedContent()

        var expected = Drafty(
            text: "Alice Johnson This is a reply to replyThis is a Reply -> Forward -> Reply.",
            fmt: [
                Style(at: 0, len: 13, key: 0),
                Style(tp: "BR", at: 13,len: 1),
                Style(tp: "QQ", at: 0, len: 38)
            ],
            ent: [Entity(tp: "MN", data: ["val": .string("usr123abcDE")])]
        )
        XCTAssertEqual(expected, actual, "Forward 1 has failed")

        // ------- Forward 2 (mention stripped).
        src = Drafty(
            text: "➦ Alice Johnson Alice Johnson This is a simple replyThis is a reply to reply",
            fmt: [
                Style(at: 0, len: 15, key: 0),
                Style(tp: "BR", at: 15,len: 1),
                Style(at: 16, len: 13, key: 1),
                Style(tp: "BR", at: 29,len: 1),
                Style(tp: "QQ", at: 16, len: 36)
            ],
            ent: [
                Entity(tp: "MN", data: ["val": .string("usr123abcDE")]),
                Entity(tp: "MN", data: ["val": .string("usr123abcDE")])
            ]
        )
        actual = src.forwardedContent();
        expected = Drafty(
            text: "Alice Johnson This is a simple replyThis is a reply to reply",
            fmt: [
                Style(at: 0, len: 13, key: 0),
                Style(tp: "BR", at: 13,len: 1),
                Style(tp: "QQ", at: 0, len: 36)
            ],
            ent: [
                Entity(tp: "MN", data: ["val": .string("usr123abcDE")])
            ]
        )
        XCTAssertEqual(expected, actual, "Forward 2 has failed")
    }

    func testPreview() {
        // ------- Preview 1.
        var src = Drafty(
            text: "Alice Johnson This is a reply to replyThis is a Reply -> Forward -> Reply.",
            fmt: [
                Style(at: 0, len: 13, key: 0),
                Style(tp: "BR", at: 13, len: 1),
                Style(tp: "QQ", at: 0, len: 38)],
            ent: [
                Entity(tp: "MN", data: ["val": .string("usr123abcDE")])
            ]
        )
        var actual = src.preview(previewLen: 25);
        var expected = Drafty(
            text: " This is a Reply -> Forw…",
            fmt: [Style(tp: "QQ", at: 0, len: 1)],
            ent: nil
        )
        XCTAssertEqual(expected, actual, "Preview 1 has failed")

        // ------- Preview 2.
        src = Drafty(
            text: "➦ Alice Johnson Alice Johnson This is a simple replyThis is a reply to reply",
            fmt: [
                Style(at: 0, len: 15, key: 0),
                Style(tp: "BR", at: 15,len: 1),
                Style(at: 16, len: 13, key: 1),
                Style(tp: "BR", at: 29,len: 1),
                Style(tp: "QQ", at: 16, len: 36)
            ],
            ent: [
                Entity(tp: "MN", data: ["val": .string("usr123abcDE")]),
                Entity(tp: "MN", data: ["val": .string("usr123abcDE")])
            ]
        )
        actual = src.preview(previewLen: 25);
        expected = Drafty(
            text: "➦  This is a reply to re…",
            fmt: [
                Style(at: 0, len: 1, key: 0),
                Style(tp: "QQ", at: 2, len: 1)
            ],
            ent: [
                Entity(tp: "MN", data: ["val": .string("usr123abcDE")])
            ]
        )
        XCTAssertEqual(expected, actual, "Preview 2 has failed")
    }

    func testReply() {
        // --------- Reply 1
        var src = Drafty(
            text: "Alice Johnson This is a reply to replyThis is a Reply -> Forward -> Reply.",
            fmt: [
                Style(at: 0, len: 13, key: 0),
                Style(tp: "BR", at: 13,len: 1),
                Style(tp: "QQ", at: 0, len: 38)
            ],
            ent: [
                Entity(tp: "MN", data: ["val": .string("usr123abcDE")])
            ]
        )
        var actual = src.replyContent(length: 25, maxAttachments: 3);
        var expected = Drafty(plainText: "This is a Reply -> Forwa…")
        XCTAssertEqual(expected, actual, "Reply 1 has failed");

        // ----------- Reply 2
        src = Drafty(
            text: "➦ Alice Johnson Alice Johnson This is a simple replyThis is a reply to reply",
            fmt: [
                Style(at: 0, len: 15, key: 0),
                Style(tp: "BR", at: 15,len: 1),
                Style(at: 16, len: 13, key: 1),
                Style(tp: "BR", at: 29,len: 1),
                Style(tp: "QQ", at: 16, len: 36)
            ],
            ent: [
                Entity(tp: "MN", data: ["val": .string("usr123abcDE")]),
                Entity(tp: "MN", data: ["val": .string("usr123abcDE")])
            ]
        )
        actual = src.replyContent(length: 25, maxAttachments: 3);
        expected = Drafty(
            text: "➦ This is a reply to rep…",
            fmt: [
                Style(tp: "MN", at: 0, len: 1)
            ],
            ent: nil
        )
        XCTAssertEqual(expected, actual, "Reply 2 has failed");

        // ----------- Reply 3
        src = Drafty(
            text: "Message with attachment",
            fmt: [
                Style(at: -1, len: 0, key: 0),
                Style(tp: "ST", at: 8,len: 4)
            ],
            ent: [
                Entity(tp: "EX", data: [
                    "mime": .string("image/jpeg"),
                    "val": .string("<1292, bytes: /9j/4AAQSkZJ.123456789012345678901234567890123456789012345678901234567890.rehH5o6D/9k=>"),
                    "width": .int(25),
                    "height": .int(14),
                    "size": .int(968),
                    "name": .string("hello.jpg")
                ])
            ]
        )
        actual = src.replyContent(length: 25, maxAttachments: 3);
        expected = Drafty(
            text: "Message with attachment ",
            fmt: [
                Style(tp: "ST", at: 8,len: 4),
                Style(at: 23, len: 1, key: 0)
            ],
            ent: [
                Entity(tp: "EX", data: [
                    "mime": .string("image/jpeg"),
                    "width": .int(25),
                    "height": .int(14),
                    "size": .int(968),
                    "name": .string("hello.jpg")
                ])
            ]
        )
        XCTAssertEqual(expected, actual, "Reply 3 has failed")

        // ----------- Reply 4
        src = Drafty(
            text: "",
            fmt: [
                Style(at: -1, len: 0, key: 0)
            ],
            ent: [
                Entity(tp: "EX", data: [
                        "mime": .string("image/jpeg"),
                        "val": .string("<1292, bytes: /9j/4AAQSkZJ.123456789012345678901234567890123456789012345678901234567890.rehH5o6D/9k=>"),
                        "width": .int(25),
                        "height": .int(14),
                        "size": .int(968),
                        "name": .string("hello.jpg"),
                ])
            ]
        )
        actual = src.replyContent(length: 25, maxAttachments: 3);
        expected = Drafty(
            text: " ",
            fmt: [
                Style(at: 0, len: 1, key: 0)
            ],
            ent: [
                Entity(tp: "EX", data: [
                        "mime": .string("image/jpeg"),
                        "width": .int(25),
                        "height": .int(14),
                        "size": .int(968),
                        "name": .string("hello.jpg"),
                ])
            ]
        )
        XCTAssertEqual(expected, actual, "Reply 4 has failed")

        // ------- Reply 5 (inline image)
        src = Drafty(
            text: " ",
            fmt: [Style(at: 0, len: 1, key: 0)],
            ent: [Entity(
                tp: "IM",
                data: [
                    "height": .int(213),
                    "width": .int(638),
                    "name": .string("roses.jpg"),
                    "val": .string("<38992, 123456789012345678901234567890123456789012345678901234567890 bytes: ...>"),
                    "mime":.string("image/jpeg")
                ])
            ]
        )
        actual = src.replyContent(length: 25, maxAttachments: 3);
        expected = Drafty(
            text: " ",
            fmt: [Style(at: 0, len: 1, key: 0)],
            ent: [Entity(
                tp: "IM",
                data: [
                    "height": .int(213),
                    "width": .int(638),
                    "name": .string("roses.jpg"),
                    "val": .string("<38992, 123456789012345678901234567890123456789012345678901234567890 bytes: ...>"),
                    "mime": .string("image/jpeg")
                ])
            ]
        )
        XCTAssertEqual(expected, actual, "Reply 5 has failed");

    }

    func testFormat() {
        // --------- Format 1
        var src = Drafty(
            text: "Alice Johnson This is a reply to replyThis is a Reply -> Forward -> Reply." ,
            fmt: [
                Style(at: 0, len: 13, key: 0),
                Style(tp: "BR", at: 13,len: 1),
                Style(tp: "ST", at: 0, len: 38)
            ],
            ent: [
                Entity(tp: "MN", data: ["val": .string("usr123abcDE")])
            ]
        )
        var actual = src.toMarkdown(withPlainLinks: false)
        var expected = "*@Alice Johnson\nThis is a reply to reply*This is a Reply -> Forward -> Reply.";
        XCTAssertEqual(expected, actual, "Format 1 has failed")

        // --------- Format 2

        src = Drafty(
            text: "an url: https://www.example.com/abc#fragment and another www.tinode.co",
            fmt: [
                Style(tp: "EM", at: 57, len: 13),
                Style(at: 8, len: 36, key: 0),
                Style(at: 57, len: 13, key: 1)
            ],
            ent: [
                Entity(tp: "LN", data: ["url": .string("https://www.example.com/abc#fragment")]),
                Entity(tp: "LN", data: ["url": .string("http://www.tinode.co")])
            ]
        )
        actual = src.toMarkdown(withPlainLinks: false)
        expected = "an url: [https://www.example.com/abc#fragment](https://www.example.com/abc#fragment) and another _[www.tinode.co](http://www.tinode.co)_"
        XCTAssertEqual(expected, actual, "Format 2 has failed")
    }

    func testPerformanceParse() {
        self.measure {
            for i in 0..<10000 {
                _ = Drafty(content: "*abcd _\(i)_*\nsecond line https://www.example.com/ @mention")
            }
        }
    }

}
