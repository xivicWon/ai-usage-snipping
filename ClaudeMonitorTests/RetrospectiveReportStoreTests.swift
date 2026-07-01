// ClaudeMonitorTests/RetrospectiveReportStoreTests.swift
import XCTest
@testable import ClaudeMonitor

final class RetrospectiveReportStoreTests: XCTestCase {
    var sut: RetrospectiveReportStore!

    override func setUp() {
        super.setUp()
        sut = try! RetrospectiveReportStore(path: ":memory:")
    }

    private func report(_ id: String, gen: Date, body: String = "## 관찰\n내용") -> RetrospectiveReport {
        RetrospectiveReport(id: id, periodLabel: "최근 7일",
                            from: gen.addingTimeInterval(-7 * 86400), to: gen,
                            generatedAt: gen, body: body, humanSessions: 67, botSessions: 405)
    }

    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    func test_latest_nil_when_empty() throws {
        XCTAssertNil(try sut.latest())
    }

    func test_save_then_latest_roundtrip() throws {
        let r = report("A", gen: t0, body: "## 관찰\n67세션")
        try sut.save(r)
        XCTAssertEqual(try sut.latest(), r)
    }

    func test_latest_returns_newest_by_generatedAt() throws {
        try sut.save(report("old", gen: t0))
        try sut.save(report("new", gen: t0.addingTimeInterval(3600)))
        XCTAssertEqual(try sut.latest()?.id, "new")
    }

    func test_all_is_newest_first() throws {
        try sut.save(report("old", gen: t0))
        try sut.save(report("new", gen: t0.addingTimeInterval(3600)))
        XCTAssertEqual(try sut.all().map(\.id), ["new", "old"])
    }

    func test_count_reflects_saved() throws {
        XCTAssertEqual(try sut.count(), 0)
        try sut.save(report("a", gen: t0))
        try sut.save(report("b", gen: t0.addingTimeInterval(60)))
        XCTAssertEqual(try sut.count(), 2)
    }

    func test_deleteAll_clears() throws {
        try sut.save(report("a", gen: t0))
        try sut.deleteAll()
        XCTAssertEqual(try sut.count(), 0)
        XCTAssertNil(try sut.latest())
    }

    func test_save_is_idempotent_by_id() throws {
        try sut.save(report("A", gen: t0, body: "first"))
        try sut.save(report("A", gen: t0, body: "second"))
        XCTAssertEqual(try sut.all().count, 1)
        XCTAssertEqual(try sut.latest()?.body, "second")
    }
}
