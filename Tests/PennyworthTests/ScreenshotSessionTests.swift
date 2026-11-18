import CoreGraphics
import XCTest
@testable import Pennyworth

// MARK: - Fakes

final class FakeCapturer: ScreenCapturing {
    var snapshot: ScreenSnapshot?
    var delayNanoseconds: UInt64 = 0
    private(set) var captureCount = 0

    func capture() async throws -> ScreenSnapshot {
        captureCount += 1
        if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }
        guard let snapshot else { throw ScreenshotError.captureFailed }
        return snapshot
    }
}

@MainActor
final class FakeOverlay: ScreenshotOverlayPresenting {
    private(set) var presentCount = 0
    private(set) var dismissCount = 0
    private(set) var sessionDelegate: ScreenshotOverlayViewDelegate?
    private(set) var hidden = false
    var selection: (display: CapturedDisplay, rect: CGRect, annotations: [Annotation])?

    func present(snapshot: ScreenSnapshot, delegate: ScreenshotOverlayViewDelegate) {
        presentCount += 1
        sessionDelegate = delegate
    }

    func dismiss() {
        dismissCount += 1
        selection = nil
    }

    func setOverlaysHidden(_ hidden: Bool) {
        self.hidden = hidden
    }

    var currentSelection: (display: CapturedDisplay, rect: CGRect, annotations: [Annotation])? { selection }
}

@MainActor
final class FakeOutput: ScreenshotOutputHandling {
    var copied: [RenderedScreenshot] = []
    var pinned: [RenderedScreenshot] = []
    var copyError: Error?
    var saveResult: ScreenshotSaveResult = .cancelled
    var saveError: Error?
    private(set) var pinClipboardCount = 0

    func copy(_ screenshot: RenderedScreenshot) throws {
        if let copyError { throw copyError }
        copied.append(screenshot)
    }

    func save(_ screenshot: RenderedScreenshot) async throws -> ScreenshotSaveResult {
        if let saveError { throw saveError }
        return saveResult
    }

    func pin(_ screenshot: RenderedScreenshot) throws {
        pinned.append(screenshot)
    }

    func pinClipboard() throws { pinClipboardCount += 1 }
}

// MARK: - Tests

@MainActor
final class ScreenshotSessionTests: XCTestCase {
    private func makeDisplay() -> CapturedDisplay {
        let descriptor = DisplayDescriptor(id: 1, quartzFrame: CGRect(x: 0, y: 0, width: 2, height: 2),
                                           cocoaFrame: CGRect(x: 0, y: 0, width: 2, height: 2))
        let provider = CGDataProvider(data: Data([UInt8](repeating: 128, count: 64)) as CFData)!
        let image = CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return CapturedDisplay(descriptor: descriptor, image: image)
    }

    private func makeSnapshot() -> ScreenSnapshot {
        ScreenSnapshot(displays: [makeDisplay()], windows: [])
    }

    private func waitFor(_ condition: @escaping @MainActor () -> Bool, timeout: TimeInterval = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private func assertWait(_ condition: @escaping @MainActor () -> Bool,
                            file: StaticString = #filePath, line: UInt = #line) async {
        let ok = await waitFor(condition)
        XCTAssertTrue(ok, file: file, line: line)
    }

    private func makeSession(authorized: Bool = true, access suppliedAccess: FakeAccess? = nil,
                             settingsOpener: FakeSettingsOpener? = nil)
        -> (ScreenshotSessionController, FakeCapturer, FakeOverlay, FakeOutput, FakeGuidance) {
        let access = suppliedAccess ?? FakeAccess(results: [authorized])
        let guidance = FakeGuidance(choices: [.cancel])
        let permission = ScreenCapturePermissionCoordinator(access: access, guidance: guidance,
                                                            settingsOpener: settingsOpener ?? FakeSettingsOpener())
        let capturer = FakeCapturer()
        capturer.snapshot = makeSnapshot()
        let overlay = FakeOverlay()
        let output = FakeOutput()
        let session = ScreenshotSessionController(capturer: capturer, permission: permission,
                                                  overlay: overlay, output: output)
        return (session, capturer, overlay, output, guidance)
    }

    func testFullCaptureFlowPresentsOverlay() async throws {
        let (session, _, overlay, _, _) = makeSession()
        var willCapture = 0
        session.onWillCapture = { willCapture += 1 }
        try session.startScreenshot()
        await assertWait { overlay.presentCount == 1 }
        XCTAssertEqual(session.phase, .selecting)
        XCTAssertEqual(willCapture, 1)
    }

    func testRepeatedStartDoesNotRecapture() async throws {
        let (session, capturer, overlay, _, _) = makeSession()
        try session.startScreenshot()
        await assertWait { overlay.presentCount == 1 }
        try session.startScreenshot()
        try session.startScreenshot()
        XCTAssertEqual(capturer.captureCount, 1)
        XCTAssertEqual(session.phase, .selecting)
    }

    func testConfirmWithoutSelectionDoesNothing() async throws {
        let (session, _, overlay, output, _) = makeSession()
        try session.startScreenshot()
        await assertWait { overlay.presentCount == 1 }
        session.confirmSelection()
        XCTAssertTrue(output.copied.isEmpty)
        XCTAssertEqual(session.phase, .selecting)
        XCTAssertEqual(overlay.dismissCount, 0)
    }

    func testConfirmCopiesComposedImageAndFinishes() async throws {
        let (session, _, overlay, output, _) = makeSession()
        try session.startScreenshot()
        await assertWait { overlay.presentCount == 1 }
        overlay.selection = (display: makeDisplay(), rect: CGRect(x: 0, y: 0, width: 1, height: 1), annotations: [])
        session.overlayView(makeViewStub(), didChangeSelection: overlay.selection?.rect)
        session.confirmSelection()
        XCTAssertEqual(output.copied.count, 1)
        XCTAssertEqual(output.copied.first?.cgImage.width, 2)
        XCTAssertEqual(output.copied.first?.pointSize, CGSize(width: 1, height: 1))
        XCTAssertEqual(session.phase, .idle)
        XCTAssertEqual(overlay.dismissCount, 1)
    }

    func testEscapeCancelsAndRestoresFocus() async throws {
        let (session, _, overlay, _, _) = makeSession()
        try session.startScreenshot()
        await assertWait { overlay.presentCount == 1 }
        var restored = 0
        session.onCancelRestoreFocus = { restored += 1 }
        session.cancel()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertEqual(overlay.dismissCount, 1)
        XCTAssertEqual(restored, 1)
    }

    func testLateCaptureResultAfterCancelIsDiscarded() async throws {
        let (session, capturer, overlay, _, _) = makeSession()
        capturer.delayNanoseconds = 100_000_000
        try session.startScreenshot()
        // Wait until capture is actually in flight, then cancel before its result arrives.
        await assertWait { capturer.captureCount == 1 }
        session.cancel()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(overlay.presentCount, 0)
        XCTAssertEqual(session.phase, .idle)
    }

    func testCopyFailureKeepsSelectionAndSessionAlive() async throws {
        let (session, _, overlay, output, _) = makeSession()
        try session.startScreenshot()
        await assertWait { overlay.presentCount == 1 }
        overlay.selection = (display: makeDisplay(), rect: CGRect(x: 0, y: 0, width: 1, height: 1), annotations: [])
        output.copyError = ScreenshotError.clipboardWriteFailed
        var errors: [Error] = []
        session.onError = { errors.append($0) }
        session.confirmSelection()
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(session.phase, .annotating)
        XCTAssertEqual(overlay.dismissCount, 0)
        XCTAssertNotNil(overlay.selection)
    }

    func testSystemPermissionRequestEndsWithoutCaptureOrAppGuidance() async throws {
        let (session, capturer, overlay, _, guidance) = makeSession(authorized: false)
        try session.startScreenshot()
        await assertWait { session.phase == .idle }
        XCTAssertEqual(capturer.captureCount, 0)
        XCTAssertEqual(overlay.presentCount, 0)
        XCTAssertEqual(guidance.presentations, 0)
    }

    func testPermissionHandoffDoesNotStealFocusFromSystemUI() async throws {
        let (session, capturer, _, _, guidance) = makeSession(authorized: false)
        var restored = 0
        session.onCancelRestoreFocus = { restored += 1 }
        try session.startScreenshot()
        await assertWait { session.phase == .idle }
        XCTAssertEqual(restored, 0)

        guidance.choices = [.openSettings]
        try session.startScreenshot()
        await assertWait { session.phase == .idle }
        XCTAssertEqual(guidance.presentations, 1)
        XCTAssertEqual(restored, 0)
        XCTAssertEqual(capturer.captureCount, 0)
    }

    func testScreenshotResumesAfterPermissionGrantedBetweenAttempts() async throws {
        let access = FakeAccess(results: [false])
        let (session, capturer, overlay, _, guidance) = makeSession(access: access)
        try session.startScreenshot()
        await assertWait { session.phase == .idle }
        guidance.choices = [.openSettings]
        try session.startScreenshot()
        await assertWait { session.phase == .idle }
        XCTAssertEqual(capturer.captureCount, 0)

        access.results = [true]
        try session.startScreenshot()
        await assertWait { overlay.presentCount == 1 }
        XCTAssertEqual(session.phase, .selecting)
        XCTAssertEqual(capturer.captureCount, 1)
        XCTAssertEqual(access.requestCount, 1)
        XCTAssertEqual(guidance.presentations, 1)
    }

    func testPermissionSettingsFailureReportsErrorWithoutCapturing() async throws {
        let opener = FakeSettingsOpener()
        opener.result = false
        let (session, capturer, overlay, _, guidance) = makeSession(authorized: false, settingsOpener: opener)
        var errors: [Error] = []
        session.onError = { errors.append($0) }
        try session.startScreenshot()
        await assertWait { session.phase == .idle }
        guidance.choices = [.openSettings]
        try session.startScreenshot()
        await assertWait { session.phase == .idle }
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first as? ScreenshotError, .permissionSettingsFailed)
        XCTAssertEqual(capturer.captureCount, 0)
        XCTAssertEqual(overlay.presentCount, 0)
    }

    func testCaptureErrorReportsAndReturnsToIdle() async throws {
        let (session, capturer, _, _, _) = makeSession()
        capturer.snapshot = nil
        var errors: [Error] = []
        session.onError = { errors.append($0) }
        try session.startScreenshot()
        await assertWait { !errors.isEmpty }
        XCTAssertEqual(session.phase, .idle)
    }

    func testPinClipboardForwardsToOutput() throws {
        let (session, _, _, output, _) = makeSession()
        try session.pinClipboardImage()
        XCTAssertEqual(output.pinClipboardCount, 1)
    }

    // MARK: - Save / Pin

    func testSaveCancelledRestoresOverlayAndAnnotations() async throws {
        let (session, _, overlay, output, _) = makeSession()
        output.saveResult = .cancelled
        try session.startScreenshot()
        await assertWait { overlay.presentCount == 1 }
        overlay.selection = (display: makeDisplay(), rect: CGRect(x: 0, y: 0, width: 1, height: 1), annotations: [])
        session.saveSelection()
        XCTAssertTrue(overlay.hidden)
        await assertWait { session.phase == .annotating }
        XCTAssertFalse(overlay.hidden)
        XCTAssertEqual(overlay.dismissCount, 0)
        XCTAssertNotNil(overlay.selection)
    }

    func testSaveSuccessFinishesSession() async throws {
        let (session, _, overlay, output, _) = makeSession()
        output.saveResult = .saved(URL(fileURLWithPath: "/tmp/test.png"))
        try session.startScreenshot()
        await assertWait { overlay.presentCount == 1 }
        overlay.selection = (display: makeDisplay(), rect: CGRect(x: 0, y: 0, width: 1, height: 1), annotations: [])
        session.saveSelection()
        await assertWait { session.phase == .idle }
        XCTAssertEqual(overlay.dismissCount, 1)
    }

    func testSaveFailureKeepsSessionAlive() async throws {
        let (session, _, overlay, output, _) = makeSession()
        output.saveError = ScreenshotError.saveFailed
        var errors: [Error] = []
        session.onError = { errors.append($0) }
        try session.startScreenshot()
        await assertWait { overlay.presentCount == 1 }
        overlay.selection = (display: makeDisplay(), rect: CGRect(x: 0, y: 0, width: 1, height: 1), annotations: [])
        session.saveSelection()
        await assertWait { !errors.isEmpty }
        XCTAssertEqual(session.phase, .annotating)
        XCTAssertFalse(overlay.hidden)
        XCTAssertEqual(overlay.dismissCount, 0)
    }

    func testPinComposesWithAnnotationsAndFinishes() async throws {
        let (session, _, overlay, output, _) = makeSession()
        try session.startScreenshot()
        await assertWait { overlay.presentCount == 1 }
        let annotation = Annotation(geometry: .rectangle(CGRect(x: 0, y: 0, width: 1, height: 1)), style: .default)
        overlay.selection = (display: makeDisplay(), rect: CGRect(x: 0, y: 0, width: 1, height: 1),
                             annotations: [annotation])
        session.pinSelection()
        XCTAssertEqual(output.pinned.count, 1)
        XCTAssertEqual(output.pinned.first?.cgImage.width, 2)
        XCTAssertEqual(session.phase, .idle)
        XCTAssertEqual(overlay.dismissCount, 1)
    }

    func testConfirmUsesAnnotationsInComposedImage() async throws {
        let (session, _, overlay, output, _) = makeSession()
        try session.startScreenshot()
        await assertWait { overlay.presentCount == 1 }
        let annotation = Annotation(geometry: .rectangle(CGRect(x: 0, y: 0, width: 1, height: 1)), style: .default)
        overlay.selection = (display: makeDisplay(), rect: CGRect(x: 0, y: 0, width: 1, height: 1),
                             annotations: [annotation])
        session.confirmSelection()
        XCTAssertEqual(output.copied.count, 1)
        // The annotated path renders through NSBitmapImageRep, preserving physical pixels.
        XCTAssertEqual(output.copied.first?.cgImage.width, 2)
        XCTAssertEqual(session.phase, .idle)
    }

    /// The session delegate methods take a view; a minimal real view is enough for routing tests.
    private func makeViewStub() -> ScreenshotOverlayView {
        ScreenshotOverlayView(frame: NSRect(x: 0, y: 0, width: 2, height: 2), display: makeDisplay(),
                              windows: [], mainDisplayHeight: 2, ownPID: 1)
    }
}
