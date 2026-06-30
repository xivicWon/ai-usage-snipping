// ClaudeMonitorTests/SessionFeatureStoreTests.swift
import XCTest
@testable import ClaudeMonitor

final class SessionFeatureStoreTests: XCTestCase {
    var sut: SessionFeatureStore!

    override func setUp() {
        super.setUp()
        sut = try! SessionFeatureStore(path: ":memory:")
    }

    private func make(id: String, goals: Int = 1, started: Date? = nil,
                      tools: [String: Int] = ["Edit": 2], files: [String] = ["/p/A.swift"],
                      isBot: Bool = false) -> SessionFeatures {
        SessionFeatures(
            sessionId: id, source: "claude", projectPath: "/p",
            goalCount: goals, toolCounts: tools, filesEdited: files,
            testTouched: false, errorCount: 0, interruptCount: 0, totalTokens: 100,
            startedAt: started, endedAt: started, isBot: isBot
        )
    }

    func test_isBot_flag_roundtrips() throws {
        try sut.upsert(make(id: "BOT", started: day, isBot: true))
        let got = try sut.features(from: day.addingTimeInterval(-60), to: day.addingTimeInterval(60)).first
        XCTAssertEqual(got?.isBot, true)
    }

    private let day = Date(timeIntervalSince1970: 1_750_000_000)  // fixed, whole-second

    func test_count_empty_is_zero() throws {
        XCTAssertEqual(try sut.count(), 0)
    }

    func test_upsert_then_fetch_roundtrip() throws {
        let f = make(id: "S1", goals: 3, started: day)
        try sut.upsert(f)
        let got = try sut.features(from: day.addingTimeInterval(-60), to: day.addingTimeInterval(60))
        XCTAssertEqual(got, [f])
    }

    func test_upsert_is_idempotent_by_sessionId() throws {
        try sut.upsert(make(id: "S1", goals: 1, started: day))
        try sut.upsert(make(id: "S1", goals: 5, started: day))   // 같은 세션 재적재 → 최신으로 교체
        XCTAssertEqual(try sut.count(), 1)
        let got = try sut.features(from: day.addingTimeInterval(-60), to: day.addingTimeInterval(60))
        XCTAssertEqual(got.first?.goalCount, 5)
    }

    func test_features_filters_by_startedAt_window() throws {
        try sut.upsert(make(id: "IN", started: day))
        try sut.upsert(make(id: "OUT", started: day.addingTimeInterval(-7 * 24 * 3600)))
        let got = try sut.features(from: day.addingTimeInterval(-3600), to: day.addingTimeInterval(3600))
        XCTAssertEqual(got.map(\.sessionId), ["IN"])
    }

    func test_preserves_toolCounts_and_filesEdited_json() throws {
        let f = make(id: "S1", started: day, tools: ["Edit": 2, "Bash": 5], files: ["/p/A.swift", "/p/B.swift"])
        try sut.upsert(f)
        let got = try sut.features(from: day.addingTimeInterval(-60), to: day.addingTimeInterval(60)).first
        XCTAssertEqual(got?.toolCounts, ["Edit": 2, "Bash": 5])
        XCTAssertEqual(got?.filesEdited, ["/p/A.swift", "/p/B.swift"])
    }
}
