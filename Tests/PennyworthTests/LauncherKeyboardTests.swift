@testable import Pennyworth
import AppKit
import Carbon
import XCTest

final class LauncherKeyboardTests: XCTestCase {
    @MainActor func testReturnInSearchFieldOpensSelectedApplication() throws {
        try withLauncher { panel, controller, model, executor in
            controller.focusSearchField(reset: false)
            XCTAssertTrue(panel.firstResponder is NSTextView)
            panel.sendEvent(try returnEvent(in: panel))
            XCTAssertEqual(executor.actions, [.openApplication(Self.dockerURL)])
            XCTAssertTrue(model.isExecuting)
        }
    }

    @MainActor func testReturnInResultsTableOpensSelectedApplication() throws {
        try withLauncher { panel, controller, model, executor in
            let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
            XCTAssertTrue(panel.makeFirstResponder(table))
            XCTAssertEqual(table.selectedRow, 0)
            XCTAssertEqual(model.snapshot.results.first?.title, "Docker")
            XCTAssertEqual(model.selectedID, model.snapshot.results.first?.id)
            panel.sendEvent(try returnEvent(in: panel))
            XCTAssertEqual(executor.actions, [.openApplication(Self.dockerURL)])
            XCTAssertTrue(model.isExecuting)
        }
    }

    @MainActor func testKeypadEnterInResultsTableOpensSelectedApplication() throws {
        try withLauncher { panel, controller, _, executor in
            let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
            XCTAssertTrue(panel.makeFirstResponder(table))
            panel.sendEvent(try keyEvent(in: panel, characters: "\u{3}", keyCode: kVK_ANSI_KeypadEnter))
            XCTAssertEqual(executor.actions, [.openApplication(Self.dockerURL)])
        }
    }

    @MainActor func testReturnAfterMovingTableSelectionOpensHighlightedApplicationOnce() throws {
        try withLauncher { panel, controller, model, executor in
            let secondURL = URL(fileURLWithPath: "/Applications/Docker Tools.app")
            model.setApplications([AppItem(name: "Docker", url: Self.dockerURL),
                                   AppItem(name: "Docker Tools", url: secondURL)])
            let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
            XCTAssertTrue(panel.makeFirstResponder(table))
            panel.sendEvent(try keyEvent(in: panel, characters: "\u{f701}", keyCode: kVK_DownArrow))
            XCTAssertEqual(table.selectedRow, 1)
            XCTAssertEqual(model.selectedID, model.snapshot.results[1].id)
            panel.sendEvent(try returnEvent(in: panel))
            panel.sendEvent(try returnEvent(in: panel))
            XCTAssertEqual(executor.actions, [.openApplication(secondURL)])
        }
    }

    @MainActor func testReturnWithNoResultsDoesNotExecute() throws {
        try withLauncher { panel, controller, model, executor in
            model.updateQuery("=1/0")
            let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
            XCTAssertTrue(panel.makeFirstResponder(table))
            panel.sendEvent(try returnEvent(in: panel))
            XCTAssertTrue(executor.actions.isEmpty)
            XCTAssertFalse(model.isExecuting)
        }
    }

    private static let dockerURL = URL(fileURLWithPath: "/Applications/Docker.app")

    @MainActor private func withLauncher(
        _ body: (LauncherPanel, LauncherViewController, LauncherModel, TestExecutor) throws -> Void
    ) throws {
        _ = NSApplication.shared
        let name = "LauncherKeyboardTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let executor = TestExecutor()
        let model = LauncherModel(settings: SettingsStore(defaults: defaults),
                                  usage: UsageStore(defaults: defaults), executor: executor)
        let controller = LauncherViewController(model: model)
        let panel = LauncherPanel(contentRect: NSRect(origin: .zero, size: LauncherViewController.panelSize),
                                  styleMask: [], backing: .buffered, defer: false)
        panel.contentViewController = controller
        defer { model.endSession(); panel.orderOut(nil) }
        controller.focusSearchField()
        model.setApplications([AppItem(name: "Docker", url: Self.dockerURL)])
        model.updateQuery("docker")
        try body(panel, controller, model, executor)
    }

    @MainActor private func returnEvent(in panel: NSWindow) throws -> NSEvent {
        try keyEvent(in: panel, characters: "\r", keyCode: kVK_Return)
    }

    @MainActor private func keyEvent(in panel: NSWindow, characters: String, keyCode: Int) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                     timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                     characters: characters, charactersIgnoringModifiers: characters,
                                     isARepeat: false, keyCode: UInt16(keyCode)))
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
