// ClaudeMonitorTests/RetrospectiveAggregatorTests.swift
import XCTest
@testable import ClaudeMonitor

final class RetrospectiveAggregatorTests: XCTestCase {
    // 결정적 시각 계산을 위해 UTC 캘린더 주입
    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()

    private func at(hour: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: hour))!
    }

    private func sess(_ id: String, project: String = "/ws/proj-a", goals: Int = 2,
                      tools: [String: Int] = ["Edit": 3], files: [String] = [], testTouched: Bool = false,
                      errors: Int = 0, interrupts: Int = 0, tokens: Int = 1000,
                      hour: Int = 10, isBot: Bool = false) -> SessionFeatures {
        SessionFeatures(sessionId: id, source: "claude", projectPath: project,
                        goalCount: goals, toolCounts: tools, filesEdited: files, testTouched: testTouched,
                        errorCount: errors, interruptCount: interrupts, totalTokens: tokens,
                        startedAt: at(hour: hour), endedAt: at(hour: hour), isBot: isBot)
    }

    private func sum(_ f: [SessionFeatures]) -> WindowSummary {
        RetrospectiveAggregator.summarize(f, calendar: utc)
    }

    func test_empty_returns_empty() {
        XCTAssertEqual(sum([]), .empty)
    }

    func test_counts_human_and_bot_separately() {
        let s = sum([sess("a"), sess("b"), sess("c", isBot: true)])
        XCTAssertEqual(s.humanSessions, 2)
        XCTAssertEqual(s.botSessions, 1)
    }

    func test_sums_are_over_human_sessions_only() {
        let s = sum([
            sess("a", goals: 2, errors: 1, interrupts: 1, tokens: 100),
            sess("bot", goals: 9, errors: 9, interrupts: 9, tokens: 9999, isBot: true),
        ])
        XCTAssertEqual(s.goals, 2)
        XCTAssertEqual(s.errors, 1)
        XCTAssertEqual(s.interrupts, 1)
        XCTAssertEqual(s.tokens, 100)
    }

    func test_avg_goals_per_human_session() {
        let s = sum([sess("a", goals: 1), sess("b", goals: 3)])
        XCTAssertEqual(s.avgGoalsPerSession, 2.0, accuracy: 0.001)
    }

    func test_test_touch_rate_over_human_sessions() {
        let s = sum([sess("a", testTouched: true), sess("b", testTouched: false),
                     sess("c", testTouched: false), sess("d", testTouched: false)])
        XCTAssertEqual(s.testTouchRate, 0.25, accuracy: 0.001)
    }

    func test_top_projects_ranked_by_session_count() {
        let s = sum([sess("a", project: "/ws/alpha"), sess("b", project: "/ws/alpha"),
                     sess("c", project: "/ws/beta")])
        XCTAssertEqual(s.topProjects.first, NamedCount(name: "alpha", count: 2))
        XCTAssertEqual(s.topProjects.count, 2)
    }

    func test_top_tools_aggregated_across_human_sessions() {
        let s = sum([sess("a", tools: ["Edit": 2, "Bash": 1]),
                     sess("b", tools: ["Edit": 3, "Read": 5])])
        XCTAssertEqual(s.topTools.first, NamedCount(name: "Edit", count: 5))  // 2+3
    }

    func test_busiest_hours_from_session_starts() {
        let s = sum([sess("a", hour: 14), sess("b", hour: 14), sess("c", hour: 9)])
        XCTAssertEqual(s.busiestHours.first, 14)
    }

    func test_bot_only_input_has_zero_human_stats() {
        let s = sum([sess("x", isBot: true)])
        XCTAssertEqual(s.humanSessions, 0)
        XCTAssertEqual(s.avgGoalsPerSession, 0)
        XCTAssertEqual(s.testTouchRate, 0)
    }
}
