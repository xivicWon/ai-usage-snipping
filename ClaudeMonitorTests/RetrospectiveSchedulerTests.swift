// ClaudeMonitorTests/RetrospectiveSchedulerTests.swift
import XCTest
@testable import ClaudeMonitor

final class RetrospectiveSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func test_off_is_never_due() {
        XCTAssertFalse(RetrospectiveScheduler.isDue(interval: .off, lastGeneratedAt: nil, now: now))
        XCTAssertFalse(RetrospectiveScheduler.isDue(interval: .off,
            lastGeneratedAt: now.addingTimeInterval(-999 * 86400), now: now))
    }

    func test_never_generated_is_due() {
        XCTAssertTrue(RetrospectiveScheduler.isDue(interval: .daily, lastGeneratedAt: nil, now: now))
    }

    func test_due_when_interval_elapsed() {
        let last = now.addingTimeInterval(-25 * 3600)   // 25시간 전
        XCTAssertTrue(RetrospectiveScheduler.isDue(interval: .daily, lastGeneratedAt: last, now: now))
    }

    func test_not_due_before_interval() {
        let last = now.addingTimeInterval(-23 * 3600)   // 23시간 전 (< 24h)
        XCTAssertFalse(RetrospectiveScheduler.isDue(interval: .daily, lastGeneratedAt: last, now: now))
    }

    func test_weekly_respects_seven_days() {
        XCTAssertTrue(RetrospectiveScheduler.isDue(interval: .weekly,
            lastGeneratedAt: now.addingTimeInterval(-8 * 86400), now: now))
        XCTAssertFalse(RetrospectiveScheduler.isDue(interval: .weekly,
            lastGeneratedAt: now.addingTimeInterval(-6 * 86400), now: now))
    }

    func test_interval_maps_to_period() {
        XCTAssertEqual(RetroInterval.daily.period, .day)
        XCTAssertEqual(RetroInterval.every3Days.period, .threeDays)
        XCTAssertEqual(RetroInterval.weekly.period, .week)
        XCTAssertNil(RetroInterval.off.period)
    }
}
