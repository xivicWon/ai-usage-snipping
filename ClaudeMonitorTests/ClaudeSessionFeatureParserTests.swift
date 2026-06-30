// ClaudeMonitorTests/ClaudeSessionFeatureParserTests.swift
import XCTest
@testable import ClaudeMonitor

final class ClaudeSessionFeatureParserTests: XCTestCase {
    var tempDir: URL!
    var sut: ClaudeSessionFeatureParser!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = ClaudeSessionFeatureParser()
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - helpers

    private func write(_ lines: [String]) -> URL {
        let url = tempDir.appendingPathComponent("\(UUID().uuidString).jsonl")
        try! lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func userText(_ text: String, ts: String = "2026-06-01T10:00:00.000Z") -> String {
        let esc = text.replacingOccurrences(of: "\"", with: "\\\"")
        return "{\"type\":\"user\",\"sessionId\":\"S1\",\"cwd\":\"/Users/me/proj\",\"timestamp\":\"\(ts)\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"\(esc)\"}]}}"
    }

    private func toolResult(isError: Bool, ts: String = "2026-06-01T10:00:01.000Z") -> String {
        "{\"type\":\"user\",\"sessionId\":\"S1\",\"timestamp\":\"\(ts)\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"is_error\":\(isError),\"content\":\"out\"}]}}"
    }

    private func assistant(tools: [(String, String)] = [], inTok: Int = 0, outTok: Int = 0,
                           ts: String = "2026-06-01T10:00:02.000Z") -> String {
        let toolBlocks = tools.map { name, path in
            path.isEmpty
            ? "{\"type\":\"tool_use\",\"name\":\"\(name)\",\"input\":{}}"
            : "{\"type\":\"tool_use\",\"name\":\"\(name)\",\"input\":{\"file_path\":\"\(path)\"}}"
        }.joined(separator: ",")
        let content = "[{\"type\":\"text\",\"text\":\"ok\"}" + (toolBlocks.isEmpty ? "" : ",\(toolBlocks)") + "]"
        return "{\"type\":\"assistant\",\"sessionId\":\"S1\",\"cwd\":\"/Users/me/proj\",\"timestamp\":\"\(ts)\",\"message\":{\"role\":\"assistant\",\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":\(inTok),\"output_tokens\":\(outTok)},\"content\":\(content)}}"
    }

    // MARK: - tests

    func test_returns_nil_for_empty_file() throws {
        let url = write([])
        XCTAssertNil(try sut.parse(url))
    }

    func test_extracts_sessionId_source_and_project() throws {
        let url = write([userText("기능 추가해줘"), assistant()])
        let f = try XCTUnwrap(sut.parse(url))
        XCTAssertEqual(f.sessionId, "S1")
        XCTAssertEqual(f.source, "claude")
        XCTAssertEqual(f.projectPath, "/Users/me/proj")
    }

    func test_counts_user_goals_excluding_injections_and_interrupts() throws {
        let url = write([
            userText("README 갱신해줘"),
            userText("Base directory for this skill: /x/systematic-debugging\n# Systematic Debugging"),
            userText("[Request interrupted by user]"),
            toolResult(isError: false),
            userText("이제 테스트도 추가해줘"),
            assistant(),
        ])
        let f = try XCTUnwrap(sut.parse(url))
        XCTAssertEqual(f.goalCount, 2)   // 진짜 프롬프트 2개만
    }

    func test_counts_tool_usage_by_name() throws {
        let url = write([
            userText("작업"),
            assistant(tools: [("Edit", "/p/A.swift"), ("Bash", ""), ("Edit", "/p/B.swift")]),
        ])
        let f = try XCTUnwrap(sut.parse(url))
        XCTAssertEqual(f.toolCounts["Edit"], 2)
        XCTAssertEqual(f.toolCounts["Bash"], 1)
    }

    func test_collects_edited_files_and_detects_tests() throws {
        let url = write([
            userText("작업"),
            assistant(tools: [("Edit", "/p/Foo.swift"), ("Write", "/p/FooTests.swift")]),
        ])
        let f = try XCTUnwrap(sut.parse(url))
        XCTAssertEqual(Set(f.filesEdited), ["/p/Foo.swift", "/p/FooTests.swift"])
        XCTAssertTrue(f.testTouched)
    }

    func test_counts_tool_result_errors() throws {
        let url = write([
            userText("작업"),
            toolResult(isError: true),
            toolResult(isError: false),
            toolResult(isError: true),
            assistant(),
        ])
        let f = try XCTUnwrap(sut.parse(url))
        XCTAssertEqual(f.errorCount, 2)
    }

    func test_counts_interruptions() throws {
        let url = write([
            userText("작업"),
            userText("[Request interrupted by user]"),
            userText("[Request interrupted by user]"),
            assistant(),
        ])
        let f = try XCTUnwrap(sut.parse(url))
        XCTAssertEqual(f.interruptCount, 2)
    }

    func test_normal_session_is_not_flagged_as_bot() throws {
        let url = write([userText("기능 추가해줘"), assistant(tools: [("Edit", "/p/A.swift")])])
        let f = try XCTUnwrap(sut.parse(url))
        XCTAssertFalse(f.isBot)
    }

    func test_review_bot_session_is_flagged() throws {
        let url = write([
            userText("Review this change for security vulnerabilities."),
            assistant(tools: [("Read", "")]),
        ])
        let f = try XCTUnwrap(sut.parse(url))
        XCTAssertTrue(f.isBot)
    }

    func test_sums_tokens_across_assistant_messages() throws {
        let url = write([
            userText("작업"),
            assistant(inTok: 100, outTok: 50),
            assistant(inTok: 10, outTok: 5),
        ])
        let f = try XCTUnwrap(sut.parse(url))
        XCTAssertEqual(f.totalTokens, 165)
    }
}
