import Foundation
import XCTest
@testable import SynticApp

final class ToolRuntimeExecutorTests: XCTestCase {
    func testMoveFileDryRunLeavesFilesystemUntouched() throws {
        let fixture = try makeMoveFixture()
        defer { fixture.cleanup() }

        let executor = FileBackedToolExecutor(
            rootDirectoryURL: fixture.runtimeRootURL,
            finderContextProvider: StaticFinderContextProvider(snapshot: fixture.snapshot),
            destructiveExecutionMode: .dryRunOnly
        )
        let result = try executor.execute(plan: fixture.plan)

        XCTAssertEqual(result.outcome, .simulated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.sourceFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destinationFileURL.path))
    }

    func testMoveFileAllowExecutionMovesSelectedFile() throws {
        let fixture = try makeMoveFixture()
        defer { fixture.cleanup() }

        let executor = FileBackedToolExecutor(
            rootDirectoryURL: fixture.runtimeRootURL,
            finderContextProvider: StaticFinderContextProvider(snapshot: fixture.snapshot),
            destructiveExecutionMode: .allowExecution
        )
        let result = try executor.execute(plan: fixture.plan)

        XCTAssertEqual(result.outcome, .executed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.sourceFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.destinationFileURL.path))
    }

    func testRenameFileAllowExecutionRenamesSingleSelection() throws {
        let fixture = try makeRenameFixture()
        defer { fixture.cleanup() }

        let executor = FileBackedToolExecutor(
            rootDirectoryURL: fixture.runtimeRootURL,
            finderContextProvider: StaticFinderContextProvider(snapshot: fixture.snapshot),
            destructiveExecutionMode: .allowExecution
        )
        let result = try executor.execute(plan: fixture.plan)

        XCTAssertEqual(result.outcome, .executed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.originalFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.renamedFileURL.path))
    }

    func testRenameFileRejectsMultipleSelectedItems() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { cleanup(rootURL) }

        let fileA = rootURL.appendingPathComponent("a.txt")
        let fileB = rootURL.appendingPathComponent("b.txt")
        FileManager.default.createFile(atPath: fileA.path, contents: Data("a".utf8))
        FileManager.default.createFile(atPath: fileB.path, contents: Data("b".utf8))

        let snapshot = makeSnapshot(selectedPaths: [fileA.path, fileB.path])
        let executor = FileBackedToolExecutor(
            rootDirectoryURL: rootURL.appendingPathComponent("runtime"),
            finderContextProvider: StaticFinderContextProvider(snapshot: snapshot),
            destructiveExecutionMode: .allowExecution
        )

        let result = try executor.execute(
            plan: makePlan(intentKind: "rename_file", transcript: "rename file to merged.txt")
        )

        XCTAssertEqual(result.outcome, .rejected)
        XCTAssertTrue(result.detail.contains("exactly one selected item required"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileB.path))
    }

    private func makeMoveFixture() throws -> MoveFixture {
        let rootURL = try makeTemporaryDirectory()
        let runtimeRootURL = rootURL.appendingPathComponent("runtime", isDirectory: true)
        let sourceDirectory = rootURL.appendingPathComponent("source", isDirectory: true)
        let destinationDirectory = rootURL.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let sourceFileURL = sourceDirectory.appendingPathComponent("report.txt", isDirectory: false)
        FileManager.default.createFile(atPath: sourceFileURL.path, contents: Data("payload".utf8))
        let destinationFileURL = destinationDirectory.appendingPathComponent("report.txt", isDirectory: false)

        let plan = makePlan(
            intentKind: "move_file",
            transcript: "move file to \(destinationDirectory.path)"
        )
        let snapshot = makeSnapshot(selectedPaths: [sourceFileURL.path])

        return MoveFixture(
            rootURL: rootURL,
            runtimeRootURL: runtimeRootURL,
            sourceFileURL: sourceFileURL,
            destinationFileURL: destinationFileURL,
            plan: plan,
            snapshot: snapshot
        )
    }

    private func makeRenameFixture() throws -> RenameFixture {
        let rootURL = try makeTemporaryDirectory()
        let runtimeRootURL = rootURL.appendingPathComponent("runtime", isDirectory: true)
        let sourceDirectory = rootURL.appendingPathComponent("rename", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        let originalFileURL = sourceDirectory.appendingPathComponent("draft.txt", isDirectory: false)
        let renamedFileURL = sourceDirectory.appendingPathComponent("final.txt", isDirectory: false)
        FileManager.default.createFile(atPath: originalFileURL.path, contents: Data("payload".utf8))

        let plan = makePlan(
            intentKind: "rename_file",
            transcript: "rename file to final.txt"
        )
        let snapshot = makeSnapshot(selectedPaths: [originalFileURL.path])

        return RenameFixture(
            rootURL: rootURL,
            runtimeRootURL: runtimeRootURL,
            originalFileURL: originalFileURL,
            renamedFileURL: renamedFileURL,
            plan: plan,
            snapshot: snapshot
        )
    }

    private func makePlan(intentKind: String, transcript: String) -> ToolExecutionPlan {
        ToolExecutionPlan(
            invocationID: "test-\(UUID().uuidString)",
            transcript: transcript,
            origin: "unit_test",
            intentKind: intentKind,
            intentSummary: "summary",
            confidencePercent: 80,
            safetyDecision: "require_confirmation",
            destructive: intentKind == "move_file" || intentKind == "rename_file",
            safetyReason: "explicit_user_confirmation_required",
            moveDestinationHint: nil,
            renameTargetHint: nil,
            timerDurationHint: nil
        )
    }

    private func makeSnapshot(selectedPaths: [String]) -> FinderContextSnapshot {
        FinderContextSnapshot(
            status: selectedPaths.isEmpty ? .emptySelection : .ok,
            finderRunning: true,
            finderFrontmost: true,
            windowCount: 1,
            viewName: "list view",
            selectedPaths: selectedPaths,
            errorCode: nil,
            errorMessage: nil
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("syntic-executor-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }
}

private struct StaticFinderContextProvider: FinderContextProviding {
    let snapshot: FinderContextSnapshot

    func currentSelectionSnapshot() -> FinderContextSnapshot {
        snapshot
    }
}

private struct MoveFixture {
    let rootURL: URL
    let runtimeRootURL: URL
    let sourceFileURL: URL
    let destinationFileURL: URL
    let plan: ToolExecutionPlan
    let snapshot: FinderContextSnapshot

    func cleanup() {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private struct RenameFixture {
    let rootURL: URL
    let runtimeRootURL: URL
    let originalFileURL: URL
    let renamedFileURL: URL
    let plan: ToolExecutionPlan
    let snapshot: FinderContextSnapshot

    func cleanup() {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: rootURL)
    }
}
