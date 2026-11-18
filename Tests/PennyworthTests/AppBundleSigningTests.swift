import Foundation
import XCTest

final class AppBundleSigningTests: XCTestCase {
    func testBuildSignsCompleteBundleWithBundleIdentifier() throws {
        let directory = try makeFixture()
        let build = try run("/bin/bash", ["build.sh"], in: directory)
        XCTAssertEqual(build.status, 0, build.output)

        let bundle = directory.appendingPathComponent("Pennyworth.app").path
        let verification = try run("/usr/bin/codesign", ["--verify", "--strict", bundle], in: directory)
        XCTAssertEqual(verification.status, 0, verification.output)

        let signature = try run("/usr/bin/codesign", ["--display", "--verbose=4", bundle], in: directory)
        XCTAssertEqual(signature.status, 0, signature.output)
        XCTAssertTrue(signature.output.contains("\nIdentifier=com.clearmann.pennyworth\n"), signature.output)
        XCTAssertTrue(signature.output.contains("Signature=adhoc"), signature.output)
    }

    func testInvalidExplicitIdentityFailsWithoutAdHocFallback() throws {
        let directory = try makeFixture()
        let build = try run(
            "/bin/bash", ["build.sh"], in: directory,
            environment: ["CODE_SIGN_IDENTITY": "Pennyworth Missing Identity \(UUID().uuidString)"]
        )
        XCTAssertNotEqual(build.status, 0, build.output)
        XCTAssertFalse(build.output.contains("Done"), build.output)
    }

    func testCustomOutputLeavesDefaultBundleUntouched() throws {
        let directory = try makeFixture()
        let existing = directory.appendingPathComponent("Pennyworth.app")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let marker = existing.appendingPathComponent("keep.txt")
        try Data("keep existing app".utf8).write(to: marker)

        let output = ".build/signing output/Pennyworth.app"
        let build = try run("/bin/bash", ["build.sh"], in: directory, environment: ["APP_BUNDLE": output])
        XCTAssertEqual(build.status, 0, build.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        let verification = try run(
            "/usr/bin/codesign", ["--verify", "--strict", directory.appendingPathComponent(output).path], in: directory
        )
        XCTAssertEqual(verification.status, 0, verification.output)
    }

    func testRefusesNonAppAndUnrelatedExistingOutputDirectories() throws {
        for output in [".build", "Unrelated.app"] {
            let directory = try makeFixture()
            let existing = directory.appendingPathComponent(output)
            try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
            let marker = existing.appendingPathComponent("keep.txt")
            try Data("keep existing files".utf8).write(to: marker)

            let build = try run("/bin/bash", ["build.sh"], in: directory, environment: ["APP_BUNDLE": output])
            XCTAssertNotEqual(build.status, 0, build.output)
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        }
    }

    func testRefusesSymlinkOutput() throws {
        let directory = try makeFixture()
        let initial = try run("/bin/bash", ["build.sh"], in: directory)
        XCTAssertEqual(initial.status, 0, initial.output)
        let link = directory.appendingPathComponent(".build/linked.app")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: directory.appendingPathComponent("Pennyworth.app")
        )

        let build = try run("/bin/bash", ["build.sh"], in: directory, environment: ["APP_BUNDLE": link.path])
        XCTAssertNotEqual(build.status, 0, build.output)
        XCTAssertEqual(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
    }

    func testExplicitAdHocIdentitySupportsRebuildingAbsoluteOutput() throws {
        let directory = try makeFixture()
        let bundle = directory.appendingPathComponent(".build/absolute output/Pennyworth.app").path
        for _ in 0..<2 {
            let build = try run(
                "/bin/bash", ["build.sh"], in: directory,
                environment: ["APP_BUNDLE": bundle, "CODE_SIGN_IDENTITY": "-"]
            )
            XCTAssertEqual(build.status, 0, build.output)
        }
        let verification = try run("/usr/bin/codesign", ["--verify", "--strict", bundle], in: directory)
        XCTAssertEqual(verification.status, 0, verification.output)
    }

    private func makeFixture() throws -> URL {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("PennyworthSigningTests-\(UUID().uuidString)")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try manager.removeItem(at: directory) }

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in ["build.sh", "Info.plist"] {
            try manager.copyItem(at: repository.appendingPathComponent(name), to: directory.appendingPathComponent(name))
        }
        let release = directory.appendingPathComponent(".build/release")
        let resources = release.appendingPathComponent("Pennyworth_Pennyworth.bundle")
        try manager.createDirectory(at: resources, withIntermediateDirectories: true)
        try manager.copyItem(atPath: "/usr/bin/true", toPath: release.appendingPathComponent("Pennyworth").path)
        try Data("fixture resource\n".utf8).write(to: resources.appendingPathComponent("fixture.txt"))

        let bin = directory.appendingPathComponent("bin")
        try manager.createDirectory(at: bin, withIntermediateDirectories: true)
        let swift = bin.appendingPathComponent("swift")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: swift)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: swift.path)
        return directory
    }

    private func run(
        _ executable: String,
        _ arguments: [String],
        in directory: URL,
        environment: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment
            .filter { !["APP_BUNDLE", "CODE_SIGN_IDENTITY"].contains($0.key) }
            .merging(["PATH": "\(directory.path)/bin:/usr/bin:/bin:/usr/sbin:/sbin"]) { _, new in new }
            .merging(environment) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }
}
