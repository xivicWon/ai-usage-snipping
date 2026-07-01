// ClaudeMonitorTests/NewsDigestStoreTests.swift
import XCTest
@testable import ClaudeMonitor

final class NewsDigestStoreTests: XCTestCase {
    var sut: NewsDigestStore!

    override func setUp() {
        super.setUp()
        sut = try! NewsDigestStore(path: ":memory:")
    }

    private func digest(_ id: String, gen: Date, body: String = "- 요약1\n- 요약2") -> NewsDigest {
        NewsDigest(id: id, generatedAt: gen, body: body, itemCount: 12, sourceCount: 3)
    }

    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    func test_latest_nil_when_empty() throws {
        XCTAssertNil(try sut.latest())
    }

    func test_save_then_latest_roundtrip() throws {
        let d = digest("A", gen: t0, body: "- 첫 요약")
        try sut.save(d)
        XCTAssertEqual(try sut.latest(), d)
    }

    func test_latest_returns_newest() throws {
        try sut.save(digest("old", gen: t0))
        try sut.save(digest("new", gen: t0.addingTimeInterval(3600)))
        XCTAssertEqual(try sut.latest()?.id, "new")
    }

    func test_all_is_newest_first() throws {
        try sut.save(digest("old", gen: t0))
        try sut.save(digest("new", gen: t0.addingTimeInterval(3600)))
        XCTAssertEqual(try sut.all().map(\.id), ["new", "old"])
    }

    func test_count_and_deleteAll() throws {
        XCTAssertEqual(try sut.count(), 0)
        try sut.save(digest("a", gen: t0))
        try sut.save(digest("b", gen: t0.addingTimeInterval(60)))
        XCTAssertEqual(try sut.count(), 2)
        try sut.deleteAll()
        XCTAssertEqual(try sut.count(), 0)
        XCTAssertNil(try sut.latest())
    }

    func test_save_is_idempotent_by_id() throws {
        try sut.save(digest("A", gen: t0, body: "first"))
        try sut.save(digest("A", gen: t0, body: "second"))
        XCTAssertEqual(try sut.all().count, 1)
        XCTAssertEqual(try sut.latest()?.body, "second")
    }
}
