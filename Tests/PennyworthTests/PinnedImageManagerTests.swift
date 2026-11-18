@testable import Pennyworth
import AppKit
import XCTest

final class PinnedImageManagerTests: XCTestCase {
    @MainActor func testPinUsesPointSizeAndReturnsUniqueIdentifiers() throws {
        _ = NSApplication.shared
        let manager = PinnedImageManager()
        defer { manager.closeAll() }
        let screenshot = try makeScreenshot(pixelWidth: 40, pixelHeight: 20,
                                            pointSize: CGSize(width: 20, height: 10))

        let firstID = try manager.pin(screenshot)
        let secondID = try manager.pin(screenshot)

        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(manager.windows.count, 2)
        XCTAssertEqual(manager.windows.map(\.imageID), [firstID, secondID])
        XCTAssertEqual(manager.windows[0].frame.size, screenshot.pointSize)
        XCTAssertEqual(manager.windows[0].imageID, firstID)
        XCTAssertEqual(manager.estimatedDecodedBytes, 2 * 40 * 4 * 20)
    }

    @MainActor func testCascadingFrameCentersOffsetsAndClamps() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let pointSize = CGSize(width: 200, height: 100)

        let first = PinnedImageManager.cascadingFrame(index: 0, pointSize: pointSize,
                                                       visibleFrame: visibleFrame)
        let second = PinnedImageManager.cascadingFrame(index: 1, pointSize: pointSize,
                                                        visibleFrame: visibleFrame)
        let clamped = PinnedImageManager.cascadingFrame(index: 100, pointSize: pointSize,
                                                         visibleFrame: visibleFrame)

        XCTAssertEqual(first, CGRect(x: 300, y: 250, width: 200, height: 100))
        XCTAssertEqual(second, CGRect(x: 324, y: 226, width: 200, height: 100))
        XCTAssertEqual(second.origin.x - first.origin.x, 24)
        XCTAssertEqual(second.origin.y - first.origin.y, -24)
        XCTAssertEqual(clamped, CGRect(x: 600, y: 0, width: 200, height: 100))
        XCTAssertTrue(visibleFrame.contains(clamped))
    }

    @MainActor func testCloseRemovesOnlyMatchingWindowAndCloseAllReleasesEverything() throws {
        _ = NSApplication.shared
        let manager = PinnedImageManager()
        defer { manager.closeAll() }
        let screenshot = try makeScreenshot()
        let firstID = try manager.pin(screenshot)
        let secondID = try manager.pin(screenshot)
        let thirdID = try manager.pin(screenshot)
        let secondWindow = try XCTUnwrap(manager.windows.first { $0.imageID == secondID })

        manager.close(id: secondID)

        XCTAssertEqual(manager.windows.map(\.imageID), [firstID, thirdID])
        XCTAssertFalse(secondWindow.isVisible)
        XCTAssertNil(secondWindow.delegate)
        XCTAssertNil(secondWindow.onRequestClose)
        XCTAssertEqual(manager.estimatedDecodedBytes, 2 * 20 * 4 * 10)

        let remainingWindows = manager.windows
        manager.closeAll()

        XCTAssertTrue(manager.windows.isEmpty)
        XCTAssertEqual(manager.estimatedDecodedBytes, 0)
        XCTAssertTrue(remainingWindows.allSatisfy { !$0.isVisible })
    }

    @MainActor func testWindowWillCloseRemovesWindowThroughDelegate() throws {
        _ = NSApplication.shared
        let manager = PinnedImageManager()
        defer { manager.closeAll() }
        _ = try manager.pin(makeScreenshot())
        let window = try XCTUnwrap(manager.windows.first)

        window.close()

        XCTAssertTrue(manager.windows.isEmpty)
        XCTAssertEqual(manager.estimatedDecodedBytes, 0)
        XCTAssertNil(window.delegate)
        XCTAssertNil(window.onRequestClose)
    }

    @MainActor func testZoomClampsAndPreservesAspectRatioAndCenter() throws {
        _ = NSApplication.shared
        let screenshot = try makeScreenshot(pixelWidth: 400, pixelHeight: 200,
                                            pointSize: CGSize(width: 200, height: 100))
        let window = PinnedImageWindow(screenshot: screenshot,
                                       frame: CGRect(x: 100, y: 100, width: 200, height: 100))
        defer {
            window.onRequestClose = nil
            window.orderOut(nil)
            window.releaseImage()
        }
        let originalCenter = CGPoint(x: window.frame.midX, y: window.frame.midY)

        window.setZoom(2)
        XCTAssertEqual(window.zoom, 2)
        XCTAssertEqual(window.frame.size, CGSize(width: 400, height: 200))
        XCTAssertEqual(window.frame.width / window.frame.height, 2, accuracy: 0.0001)
        XCTAssertEqual(window.frame.midX, originalCenter.x, accuracy: 0.0001)
        XCTAssertEqual(window.frame.midY, originalCenter.y, accuracy: 0.0001)

        window.setZoom(100)
        XCTAssertEqual(window.zoom, 8)
        XCTAssertEqual(window.frame.size, CGSize(width: 1600, height: 800))

        window.setZoom(0)
        XCTAssertEqual(window.zoom, 0.1)
        XCTAssertEqual(window.frame.width, 20, accuracy: 0.0001)
        XCTAssertEqual(window.frame.height, 10, accuracy: 0.0001)
        XCTAssertEqual(window.frame.midX, originalCenter.x, accuracy: 0.0001)
        XCTAssertEqual(window.frame.midY, originalCenter.y, accuracy: 0.0001)
    }

    @MainActor func testDoubleClickAndEscapeRequestCloseWithImageID() throws {
        _ = NSApplication.shared
        let id = UUID()
        let window = PinnedImageWindow(screenshot: try makeScreenshot(),
                                       frame: CGRect(x: 0, y: 0, width: 20, height: 10),
                                       imageID: id)
        defer {
            window.onRequestClose = nil
            window.orderOut(nil)
            window.releaseImage()
        }
        var requestedIDs: [UUID] = []
        window.onRequestClose = { requestedIDs.append($0) }
        window.orderFront(nil)
        let imageView = try XCTUnwrap(window.contentView as? PinnedImageView)
        let doubleClick = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 2, pressure: 1
        ))

        imageView.mouseDown(with: doubleClick)
        window.cancelOperation(nil)

        XCTAssertEqual(requestedIDs, [id, id])
        XCTAssertTrue(window.isVisible)
    }

    @MainActor func testManagerHandlesWindowCloseRequest() throws {
        _ = NSApplication.shared
        let manager = PinnedImageManager()
        defer { manager.closeAll() }
        _ = try manager.pin(makeScreenshot())
        let window = try XCTUnwrap(manager.windows.first)

        window.cancelOperation(nil)

        XCTAssertTrue(manager.windows.isEmpty)
        XCTAssertFalse(window.isVisible)
        XCTAssertNil(window.screenshot)
    }

    @MainActor func testTwentyFirstImageThrowsWithoutEvictingExistingWindows() throws {
        _ = NSApplication.shared
        let manager = PinnedImageManager()
        defer { manager.closeAll() }
        let screenshot = try makeScreenshot(pixelWidth: 4, pixelHeight: 4)
        for _ in 0..<PinnedImageManager.maxPinnedImages {
            _ = try manager.pin(screenshot)
        }

        XCTAssertThrowsError(try manager.pin(screenshot)) { error in
            XCTAssertEqual(error as? ScreenshotError, .pinLimitExceeded)
        }
        XCTAssertEqual(manager.windows.count, PinnedImageManager.maxPinnedImages)
    }

    @MainActor func testDecodedByteBudgetThrowsWithoutChangingWindows() throws {
        _ = NSApplication.shared
        let screenshot = try makeScreenshot(pixelWidth: 4, pixelHeight: 4)
        let manager = PinnedImageManager(maxDecodedBytes: 64)
        defer { manager.closeAll() }
        _ = try manager.pin(screenshot)

        XCTAssertThrowsError(try manager.pin(screenshot)) { error in
            XCTAssertEqual(error as? ScreenshotError, .pinLimitExceeded)
        }
        XCTAssertEqual(manager.windows.count, 1)
        XCTAssertEqual(manager.estimatedDecodedBytes, 64)
    }

    private func makeScreenshot(pixelWidth: Int = 20, pixelHeight: Int = 10,
                                pointSize: CGSize? = nil,
                                bytesPerRow: Int? = nil) throws -> RenderedScreenshot {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow ?? pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        return RenderedScreenshot(
            cgImage: try XCTUnwrap(context.makeImage()),
            pointSize: pointSize ?? CGSize(width: pixelWidth, height: pixelHeight)
        )
    }
}
