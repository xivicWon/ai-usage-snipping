// ClaudeMonitorTests/ClaudeHeadlessRunnerTests.swift
import XCTest
@testable import ClaudeMonitor

private final class FakeRunner: CommandRunning {
    var stdout: String
    var exitCode: Int32
    var thrownError: Error?
    private(set) var lastArgs: [String]?
    private(set) var lastExecutable: String?

    init(stdout: String = "", exitCode: Int32 = 0, error: Error? = nil) {
        self.stdout = stdout; self.exitCode = exitCode; self.thrownError = error
    }
    func run(executable: String, args: [String], stdin: String?, timeout: TimeInterval) throws -> (stdout: String, exitCode: Int32) {
        lastExecutable = executable; lastArgs = args
        if let thrownError { throw thrownError }
        return (stdout, exitCode)
    }
}

final class ClaudeHeadlessRunnerTests: XCTestCase {

    func test_resolveExecutable_returns_first_existing() {
        let path = ClaudeHeadlessRunner.resolveExecutable(
            candidates: ["/a/claude", "/b/claude", "/c/claude"],
            exists: { $0 == "/b/claude" || $0 == "/c/claude" })
        XCTAssertEqual(path, "/b/claude")
    }

    func test_resolveExecutable_nil_when_none_exist() {
        XCTAssertNil(ClaudeHeadlessRunner.resolveExecutable(candidates: ["/a/claude"], exists: { _ in false }))
    }

    func test_unavailable_when_no_executable() {
        let sut = ClaudeHeadlessRunner(runner: FakeRunner(), candidates: ["/x/claude"], exists: { _ in false })
        XCTAssertFalse(sut.isAvailable)
        XCTAssertThrowsError(try sut.run(prompt: "hi")) { error in
            XCTAssertEqual(error as? HeadlessError, .unavailable)
        }
    }

    func test_run_returns_trimmed_text_on_success() throws {
        let fake = FakeRunner(stdout: "  회고 내용\n\n", exitCode: 0)
        let sut = ClaudeHeadlessRunner(runner: fake, candidates: ["/ok/claude"], exists: { _ in true })
        XCTAssertTrue(sut.isAvailable)
        let out = try sut.run(prompt: "PROMPT")
        XCTAssertEqual(out, "회고 내용")
        XCTAssertEqual(fake.lastArgs, ["-p", "PROMPT"])
        XCTAssertEqual(fake.lastExecutable, "/ok/claude")
    }

    func test_run_throws_failed_on_nonzero_exit() {
        let sut = ClaudeHeadlessRunner(runner: FakeRunner(stdout: "boom", exitCode: 1),
                                       candidates: ["/ok/claude"], exists: { _ in true })
        XCTAssertThrowsError(try sut.run(prompt: "x")) { error in
            XCTAssertEqual(error as? HeadlessError, .failed("boom"))
        }
    }

    func test_run_throws_failed_on_empty_output() {
        let sut = ClaudeHeadlessRunner(runner: FakeRunner(stdout: "   \n", exitCode: 0),
                                       candidates: ["/ok/claude"], exists: { _ in true })
        XCTAssertThrowsError(try sut.run(prompt: "x")) { error in
            XCTAssertEqual(error as? HeadlessError, .failed("empty output"))
        }
    }
}
