// ClaudeMonitorTests/RetrospectivePromptBuilderTests.swift
import XCTest
@testable import ClaudeMonitor

final class RetrospectivePromptBuilderTests: XCTestCase {
    private let summary = WindowSummary(
        humanSessions: 67, botSessions: 405, goals: 344, tokens: 11_255_615,
        errors: 136, interrupts: 9, avgGoalsPerSession: 5.13, testTouchRate: 0.22,
        topProjects: [NamedCount(name: "withRocky", count: 14), NamedCount(name: "total", count: 11)],
        topTools: [NamedCount(name: "Bash", count: 900), NamedCount(name: "Edit", count: 400)],
        busiestHours: [13, 2, 3])

    private func build() -> String {
        RetrospectivePromptBuilder.build(summary: summary, periodLabel: "최근 7일")
    }

    func test_includes_period_label() {
        XCTAssertTrue(build().contains("최근 7일"))
    }

    func test_includes_core_metrics() {
        let p = build()
        XCTAssertTrue(p.contains("67"))           // human sessions
        XCTAssertTrue(p.contains("5.1"))          // avg goals/session
        XCTAssertTrue(p.contains("22"))           // test touch rate %
        XCTAssertTrue(p.contains("136"))          // errors
    }

    func test_includes_top_projects_and_tools() {
        let p = build()
        XCTAssertTrue(p.contains("withRocky"))
        XCTAssertTrue(p.contains("Bash"))
    }

    func test_includes_antiplatitude_guardrails() {
        let p = build()
        XCTAssertTrue(p.contains("구체"))          // 구체적 근거 인용 요구
        XCTAssertTrue(p.contains("1~3"))          // 개선점 1~3개 제한
        XCTAssertTrue(p.contains("일반론"))        // 일반론/platitude 금지
    }

    func test_requests_korean_output() {
        XCTAssertTrue(build().contains("한국어"))
    }
}
