// ClaudeMonitorTests/AdvisorAdviceStoreTests.swift
import XCTest
@testable import ClaudeMonitor

final class AdvisorAdviceStoreTests: XCTestCase {
    var store: AdvisorAdviceStore!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() {
        super.setUp()
        store = try! AdvisorAdviceStore(path: ":memory:")
    }

    private func advice(_ id: String, _ at: Date, condition: AdvisorCondition = .stuck) -> AdvisorAdvice {
        AdvisorAdvice(id: id, condition: condition.rawValue, generatedAt: at, body: "조언 \(id)")
    }

    func test_save_and_latest() throws {
        try store.save(advice("a", now.addingTimeInterval(-100)))
        try store.save(advice("b", now))
        XCTAssertEqual(try store.latest()?.id, "b")
        XCTAssertEqual(try store.count(), 2)
    }

    func test_all_sorted_desc() throws {
        try store.save(advice("old", now.addingTimeInterval(-100)))
        try store.save(advice("new", now))
        XCTAssertEqual(try store.all().map(\.id), ["new", "old"])
    }

    func test_delete_all() throws {
        try store.save(advice("a", now))
        try store.deleteAll()
        XCTAssertEqual(try store.count(), 0)
        XCTAssertNil(try store.latest())
    }
}
