// ClaudeMonitorTests/NewsSchedulerTests.swift
import XCTest
@testable import ClaudeMonitor

final class NewsSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func test_off_is_never_due() {
        XCTAssertFalse(NewsScheduler.isDue(interval: .off, lastGeneratedAt: nil, now: now))
        XCTAssertFalse(NewsScheduler.isDue(interval: .off,
            lastGeneratedAt: now.addingTimeInterval(-999 * 86400), now: now))
    }

    func test_never_generated_is_due() {
        XCTAssertTrue(NewsScheduler.isDue(interval: .daily, lastGeneratedAt: nil, now: now))
    }

    func test_due_when_interval_elapsed() {
        XCTAssertTrue(NewsScheduler.isDue(interval: .daily,
            lastGeneratedAt: now.addingTimeInterval(-25 * 3600), now: now))
    }

    func test_not_due_before_interval() {
        XCTAssertFalse(NewsScheduler.isDue(interval: .daily,
            lastGeneratedAt: now.addingTimeInterval(-23 * 3600), now: now))
    }

    func test_weekly_respects_seven_days() {
        XCTAssertTrue(NewsScheduler.isDue(interval: .weekly,
            lastGeneratedAt: now.addingTimeInterval(-8 * 86400), now: now))
        XCTAssertFalse(NewsScheduler.isDue(interval: .weekly,
            lastGeneratedAt: now.addingTimeInterval(-6 * 86400), now: now))
    }
}
