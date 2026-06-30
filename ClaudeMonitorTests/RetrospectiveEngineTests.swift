// ClaudeMonitorTests/RetrospectiveEngineTests.swift
import XCTest
@testable import ClaudeMonitor

final class RetrospectiveEngineTests: XCTestCase {
    var features: SessionFeatureStore!
    var reports: RetrospectiveReportStore!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() {
        super.setUp()
        features = try! SessionFeatureStore(path: ":memory:")
        reports = try! RetrospectiveReportStore(path: ":memory:")
    }

    private func addSession(_ id: String, isBot: Bool, startedAt: Date) {
        try! features.upsert(SessionFeatures(
            sessionId: id, source: "claude", projectPath: "/ws/proj",
            goalCount: 2, toolCounts: ["Edit": 3], filesEdited: [], testTouched: false,
            errorCount: 1, interruptCount: 0, totalTokens: 1000,
            startedAt: startedAt, endedAt: startedAt, isBot: isBot))
    }

    private func makeEngine(generate: @escaping (String) throws -> String) -> RetrospectiveEngine {
        RetrospectiveEngine(featureStore: features, reportStore: reports,
                            generate: generate, now: { self.now }, makeId: { "fixed-id" })
    }

    func test_throws_noActivity_when_no_human_sessions() {
        addSession("bot", isBot: true, startedAt: now.addingTimeInterval(-3600))   // 봇만 있음
        let engine = makeEngine { _ in "should not be called" }
        XCTAssertThrowsError(try engine.generate(period: .week)) {
            XCTAssertEqual($0 as? RetrospectiveEngine.GenerateError, .noActivity)
        }
    }

    func test_generates_and_saves_report() throws {
        addSession("human", isBot: false, startedAt: now.addingTimeInterval(-3600))
        let engine = makeEngine { _ in "## 관찰\n생성된 회고" }
        let report = try engine.generate(period: .week)
        XCTAssertEqual(report.body, "## 관찰\n생성된 회고")
        XCTAssertEqual(report.periodLabel, "최근 7일")
        XCTAssertEqual(report.humanSessions, 1)
        XCTAssertEqual(try reports.latest(), report)   // 저장됨
    }

    func test_prompt_receives_aggregated_stats() throws {
        addSession("human", isBot: false, startedAt: now.addingTimeInterval(-3600))
        var captured = ""
        let engine = makeEngine { p in captured = p; return "본문" }
        _ = try engine.generate(period: .week)
        XCTAssertTrue(captured.contains("최근 7일"))
        XCTAssertTrue(captured.contains("일반론"))   // 가드 포함된 프롬프트
    }

    func test_propagates_generation_failure() {
        addSession("human", isBot: false, startedAt: now.addingTimeInterval(-3600))
        let engine = makeEngine { _ in throw RetrospectiveEngine.GenerateError.generationFailed("boom") }
        XCTAssertThrowsError(try engine.generate(period: .week)) {
            XCTAssertEqual($0 as? RetrospectiveEngine.GenerateError, .generationFailed("boom"))
        }
    }

    func test_excludes_sessions_outside_window() {
        addSession("old", isBot: false, startedAt: now.addingTimeInterval(-30 * 86400))  // 30일 전
        let engine = makeEngine { _ in "x" }
        XCTAssertThrowsError(try engine.generate(period: .week)) {
            XCTAssertEqual($0 as? RetrospectiveEngine.GenerateError, .noActivity)
        }
    }
}
