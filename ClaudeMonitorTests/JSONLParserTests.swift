// ClaudeMonitorTests/JSONLParserTests.swift
import XCTest
@testable import ClaudeMonitor

final class JSONLParserTests: XCTestCase {
    var tempDir: URL!
    var sut: JSONLParser!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = JSONLParser()
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // 실제 .jsonl 형식과 동일한 샘플 라인
    private let sampleLine = """
    {"type":"assistant","uuid":"msg-uuid-001","sessionId":"sess-abc","cwd":"/Users/test/proj","timestamp":"2026-06-26T09:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":200,"cache_creation_input_tokens":100}}}
    """

    func test_parses_assistant_message_fields() throws {
        let file = tempDir.appendingPathComponent("t1.jsonl")
        try sampleLine.write(to: file, atomically: true, encoding: .utf8)

        let records = try sut.parseNew(in: file)

        XCTAssertEqual(records.count, 1)
        let r = records[0]
        XCTAssertEqual(r.id, "msg-uuid-001")
        XCTAssertEqual(r.sessionId, "sess-abc")
        XCTAssertEqual(r.projectPath, "/Users/test/proj")
        XCTAssertEqual(r.model, "claude-sonnet-4-6")
        XCTAssertEqual(r.inputTokens, 1000)
        XCTAssertEqual(r.outputTokens, 500)
        XCTAssertEqual(r.cacheReadTokens, 200)
        XCTAssertEqual(r.cacheWriteTokens, 100)
    }

    func test_cost_is_calculated_from_pricing_table() throws {
        let file = tempDir.appendingPathComponent("t2.jsonl")
        try sampleLine.write(to: file, atomically: true, encoding: .utf8)

        let records = try sut.parseNew(in: file)
        // sonnet: 1000*3/1M + 500*15/1M + 200*0.3/1M + 100*3.75/1M
        let expected = 0.003 + 0.0075 + 0.00006 + 0.000375
        XCTAssertEqual(records[0].costUSD, expected, accuracy: 0.000001)
    }

    func test_skips_non_assistant_types() throws {
        let lines = """
        {"type":"user","timestamp":"2026-06-26T09:00:00.000Z"}
        {"type":"queue-operation","timestamp":"2026-06-26T09:00:00.000Z"}
        \(sampleLine)
        """
        let file = tempDir.appendingPathComponent("t3.jsonl")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        let records = try sut.parseNew(in: file)
        XCTAssertEqual(records.count, 1)
    }

    func test_incremental_parse_returns_only_new_lines() throws {
        let file = tempDir.appendingPathComponent("t4.jsonl")
        try sampleLine.write(to: file, atomically: true, encoding: .utf8)

        let first = try sut.parseNew(in: file)
        XCTAssertEqual(first.count, 1)

        // 두 번째 줄 추가
        let line2 = "\n{\"type\":\"assistant\",\"uuid\":\"msg-uuid-002\",\"sessionId\":\"sess-abc\",\"cwd\":\"/Users/test/proj\",\"timestamp\":\"2026-06-26T09:01:00.000Z\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":2000,\"output_tokens\":800,\"cache_read_input_tokens\":0,\"cache_creation_input_tokens\":0}}}"
        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(line2.data(using: .utf8)!)
        handle.closeFile()

        let second = try sut.parseNew(in: file)
        XCTAssertEqual(second.count, 1)           // 새 줄만
        XCTAssertEqual(second[0].id, "msg-uuid-002")
        XCTAssertEqual(second[0].inputTokens, 2000)
    }

    func test_empty_file_returns_empty_array() throws {
        let file = tempDir.appendingPathComponent("t5.jsonl")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let records = try sut.parseNew(in: file)
        XCTAssertTrue(records.isEmpty)
    }

    func test_assistant_message_without_usage_is_skipped() throws {
        let noUsage = "{\"type\":\"assistant\",\"uuid\":\"u1\",\"sessionId\":\"s\",\"cwd\":\"/p\",\"timestamp\":\"2026-06-26T09:00:00.000Z\",\"message\":{\"model\":\"claude-sonnet-4-6\"}}"
        let file = tempDir.appendingPathComponent("t6.jsonl")
        try noUsage.write(to: file, atomically: true, encoding: .utf8)

        let records = try sut.parseNew(in: file)
        XCTAssertTrue(records.isEmpty)
    }
}
