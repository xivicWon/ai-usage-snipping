// ClaudeMonitorTests/SQLiteStoreTests.swift
import XCTest
import GRDB
@testable import ClaudeMonitor

final class SQLiteStoreTests: XCTestCase {
    var sut: SQLiteStore!

    override func setUp() async throws {
        sut = try SQLiteStore(path: ":memory:")
    }

    private func makeRecord(id: String = UUID().uuidString,
                            inputTokens: Int = 1000,
                            outputTokens: Int = 500) -> ParsedRecord {
        ParsedRecord(
            id: id,
            sessionId: "sess-1",
            projectPath: "/Users/test/project",
            model: "claude-sonnet-4-6",
            timestamp: Date(),
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: 0,
            cacheWriteTokens: 0
        )
    }

    func test_insert_and_today_summary() throws {
        try sut.insert([makeRecord()])

        let summary = try sut.todaySummary()
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary!.totalInputTokens, 1000)
        XCTAssertEqual(summary!.totalOutputTokens, 500)
        XCTAssertGreaterThan(summary!.totalCostUSD, 0)
        XCTAssertEqual(summary!.sessionCount, 1)
    }

    func test_insert_ignores_duplicate_ids() throws {
        let record = makeRecord(id: "dup-id", inputTokens: 1000)
        try sut.insert([record])
        try sut.insert([record])  // 동일 id 재삽입

        let summary = try sut.todaySummary()
        XCTAssertEqual(summary!.totalInputTokens, 1000)  // 2000이 아님
    }

    func test_insert_multiple_records_accumulates_tokens() throws {
        try sut.insert([
            makeRecord(id: "r1", inputTokens: 1000),
            makeRecord(id: "r2", inputTokens: 2000),
        ])

        let summary = try sut.todaySummary()
        XCTAssertEqual(summary!.totalInputTokens, 3000)
    }

    func test_daily_summaries_returns_entries_for_last_30_days() throws {
        try sut.insert([makeRecord()])

        let summaries = try sut.dailySummaries(days: 30)
        XCTAssertFalse(summaries.isEmpty)
        XCTAssertGreaterThan(summaries[0].totalCostUSD, 0)
    }

    func test_today_summary_with_no_records_returns_zero_cost() throws {
        let summary = try sut.todaySummary()
        XCTAssertEqual(summary?.totalCostUSD ?? 0, 0.0)
    }
}
