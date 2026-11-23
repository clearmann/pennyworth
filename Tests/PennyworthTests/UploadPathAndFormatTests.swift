@testable import Pennyworth
import XCTest

final class UploadPathAndFormatTests: XCTestCase {
    func testTemplateExpansionResolvesAllVariablesDeterministically() {
        // 2026-11-23 08:05:09 UTC
        let date = Date(timeIntervalSince1970: 1_795_421_109)
        let utc = TimeZone(secondsFromGMT: 0)!

        let key = UploadPathFormatter.resolveObjectKey(
            template: "uPic/{year}/{month}/{day}/{hour}-{minute}-{second}/{since_second}_{since_millisecond}_{random}_{filename}{.suffix}",
            filenameWithoutExtension: "hello world",
            fileExtension: "png",
            date: date,
            randomProvider: { "AbC123" },
            timeZone: utc
        )

        XCTAssertEqual(
            key,
            "uPic/2026/11/23/08-05-09/1795421109_1795421109000_AbC123_hello world.png"
        )
    }

    func testSanitizesTraversalAndFallbackFilename() {
        let date = Date(timeIntervalSince1970: 1_795_421_109)
        let utc = TimeZone(secondsFromGMT: 0)!

        let key = UploadPathFormatter.resolveObjectKey(
            template: "/../../uPic//{filename}.{suffix}",
            filenameWithoutExtension: "   ",
            fileExtension: ".jpg",
            date: date,
            timeZone: utc
        )
        XCTAssertEqual(key, "uPic/20261123-080509.jpg")
    }

    func testPublicURLPercentEncodingAndSuffix() {
        let encoded = UploadPathFormatter.buildPublicURL(
            baseDomain: "https://cdn.example.com///",
            objectKey: "/uPic/2026/截 图 1.png",
            suffix: "?x-oss-process=image/format,webp",
            percentEncode: true
        )
        XCTAssertEqual(
            encoded,
            "https://cdn.example.com/uPic/2026/%E6%88%AA%20%E5%9B%BE%201.png?x-oss-process=image/format,webp"
        )

        let raw = UploadPathFormatter.buildPublicURL(
            baseDomain: "https://cdn.example.com/",
            objectKey: "uPic/截图.png",
            suffix: "",
            percentEncode: false
        )
        XCTAssertEqual(raw, "https://cdn.example.com/uPic/截图.png")
    }

    func testOutputFormatsEscapeSpecialCharacters() {
        let url = "https://cdn.example.com/a.png"
        XCTAssertEqual(UploadOutputFormat.url.format(url: url, filename: "demo.png"), url)
        XCTAssertEqual(
            UploadOutputFormat.markdown.format(url: url, filename: "demo [1].png"),
            "![demo \\[1\\].png](https://cdn.example.com/a.png)"
        )
        XCTAssertEqual(
            UploadOutputFormat.html.format(url: url, filename: "a\"<b&>.png"),
            "<img src=\"https://cdn.example.com/a.png\" alt=\"a&quot;&lt;b&amp;&gt;.png\"/>"
        )
        XCTAssertEqual(
            UploadOutputFormat.ubb.format(url: url, filename: "demo.png"),
            "[img]https://cdn.example.com/a.png[/img]"
        )
    }
}
