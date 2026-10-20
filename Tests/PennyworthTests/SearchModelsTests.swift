@testable import Pennyworth
import XCTest

final class SearchModelsTests: XCTestCase {
    func testRoutingPreservesPrefixesAndLiteralWords() throws {
        XCTAssertEqual(QueryParser.parse(" report")?.intent, .fileSearch(.open))
        XCTAssertEqual(QueryParser.parse("' report")?.query, "report")
        XCTAssertEqual(QueryParser.parse("find report")?.intent, .fileSearch(.reveal))
        XCTAssertEqual(QueryParser.parse("google 中文")?.intent, .web(.google))
        XCTAssertEqual(QueryParser.parse("bing notes")?.intent, .web(.bing))
        XCTAssertEqual(QueryParser.parse("ddg notes")?.intent, .web(.duckDuckGo))
        XCTAssertEqual(QueryParser.parse("123")?.intent, .applications)
        XCTAssertEqual(QueryParser.parse("Safari")?.intent, .applications)
        XCTAssertEqual(QueryParser.parse("=1+")?.explicitCalculation, true)
        XCTAssertNil(QueryParser.parse(String(repeating: "a", count: 513)))
        XCTAssertNil(try CalculatorProvider.result(for: XCTUnwrap(QueryParser.parse("Safari"))))
    }

    func testSearchURLsPreservePlusAndRejectBlankQueries() throws {
        for engine in SearchEngine.allCases {
            let result = try XCTUnwrap(WebSearchProvider.result(for: "C++ # & ?", engine: engine))
            guard case .openURL(let url) = result.action else { return XCTFail("Expected URL") }
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "C++ # & ?")
            XCTAssertFalse(url.absoluteString.contains("+"))
            XCTAssertEqual(url.scheme, "https")
            XCTAssertNil(result.fileURL)
        }
        XCTAssertNil(WebSearchProvider.result(for: "  ", engine: .google))
        XCTAssertNil(WebSearchProvider.result(for: String(repeating: "a", count: 513), engine: .bing))
    }

    func testCalculatorQueryProducesCopyResult() throws {
        let request = try XCTUnwrap(QueryParser.parse("23 * 17"))

        XCTAssertEqual(request.intent, .calculator)
        XCTAssertEqual(request.query, "23 * 17")

        let result = try XCTUnwrap(CalculatorProvider.result(for: request))
        XCTAssertEqual(result.title, "391")
        XCTAssertEqual(result.action, .copyText("391"))
    }

    func testExplicitFileQueryPreservesOpenAction() throws {
        let request = try XCTUnwrap(QueryParser.parse("open report"))

        XCTAssertEqual(request.intent, .fileSearch(.open))
        XCTAssertEqual(request.query, "report")
    }

    func testWebQueryEncodesUnicodeAndAmpersand() throws {
        let result = try XCTUnwrap(WebSearchProvider.result(for: "中文 & notes", engine: .duckDuckGo))

        XCTAssertEqual(result.title, "Search DuckDuckGo for 中文 & notes")
        XCTAssertEqual(result.action, .openURL(URL(string: "https://duckduckgo.com/?q=%E4%B8%AD%E6%96%87%20%26%20notes")!))
    }
}
