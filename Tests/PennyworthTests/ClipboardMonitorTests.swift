@testable import Pennyworth
import AppKit
import XCTest

final class ClipboardMonitorTests: XCTestCase {

    private var monitor: ClipboardMonitor!
    private var pasteboard: NSPasteboard = NSPasteboard.withUniqueName()

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        monitor = ClipboardMonitor(pasteboard: pasteboard)
    }

    override func tearDown() {
        pasteboard.clearContents()
        pasteboard.releaseGlobally()
        monitor = nil
        super.tearDown()
    }

    // MARK: - 基本检测

    func testDetectsNewText() {
        let pb = pasteboard
        pb.clearContents()
        pb.setString("test text", forType: .string)

        let item = monitor.checkPasteboard()
        XCTAssertNotNil(item)
        if case .text(let text) = item?.content {
            XCTAssertEqual(text, "test text")
        } else {
            XCTFail("Expected text content, got \(String(describing: item?.content))")
        }
    }

    func testDetectsNewFile() {
        let pb = pasteboard
        pb.clearContents()
        let url = URL(fileURLWithPath: "/tmp/test-file.txt")
        pb.writeObjects([url as NSURL])

        let item = monitor.checkPasteboard()
        XCTAssertNotNil(item)
        if case .file(let fileURL) = item?.content {
            XCTAssertEqual(fileURL, url)
        } else {
            XCTFail("Expected file content, got \(String(describing: item?.content))")
        }
    }

    func testDetectsNewImage() {
        let pb = pasteboard
        pb.clearContents()
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 100).fill()
        image.unlockFocus()
        pb.writeObjects([image])

        let item = monitor.checkPasteboard()
        XCTAssertNotNil(item)
        if case .image = item?.content {
            // 通过
        } else {
            XCTFail("Expected image content, got \(String(describing: item?.content))")
        }
    }

    func testIgnoresNoChange() {
        let item = monitor.checkPasteboard()
        XCTAssertNil(item, "changeCount 未变化时应返回 nil")
    }

    func testDetectsChangeCountChange() {
        let pb = pasteboard
        pb.clearContents()
        pb.setString("first", forType: .string)
        let item1 = monitor.checkPasteboard()
        XCTAssertNotNil(item1)

        // 再次复制新内容
        pb.clearContents()
        pb.setString("second", forType: .string)
        let item2 = monitor.checkPasteboard()
        XCTAssertNotNil(item2)
        if case .text(let text) = item2?.content {
            XCTAssertEqual(text, "second")
        }
    }

    // MARK: - 优先级：file > image > text

    func testPrioritizesFileOverText() {
        let pb = pasteboard
        pb.clearContents()
        let url = URL(fileURLWithPath: "/tmp/priority.txt")
        pb.writeObjects([url as NSURL])
        // 同时写入文本（文件 URL 通常也带文本表示）
        pb.setString(url.path, forType: .string)

        let item = monitor.checkPasteboard()
        if case .file = item?.content {
            // 正确：file 优先
        } else {
            XCTFail("Expected file to take priority, got \(String(describing: item?.content))")
        }
    }

    // MARK: - 大小限制

    func testIgnoresOversizedText() {
        let pb = pasteboard
        pb.clearContents()
        let hugeText = String(repeating: "x", count: 2 * 1024 * 1024) // 2MB
        pb.setString(hugeText, forType: .string)

        let item = monitor.checkPasteboard()
        XCTAssertNil(item, "超过 1MB 的文本应被忽略")
    }

    func testIgnoresConcealedClipboardContent() {
        let pb = pasteboard
        pb.clearContents()
        pb.setString("secret", forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))

        XCTAssertNil(monitor.checkPasteboard())
    }

    // MARK: - 时间戳

    func testItemHasRecentTimestamp() {
        let pb = pasteboard
        pb.clearContents()
        pb.setString("timestamp test", forType: .string)

        let before = Date()
        let item = monitor.checkPasteboard()
        let after = Date()

        XCTAssertNotNil(item)
        XCTAssertGreaterThanOrEqual(item!.timestamp, before)
        XCTAssertLessThanOrEqual(item!.timestamp, after)
    }
}
