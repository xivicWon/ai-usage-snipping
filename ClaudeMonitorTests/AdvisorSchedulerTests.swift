// ClaudeMonitorTests/AdvisorSchedulerTests.swift
import XCTest
@testable import ClaudeMonitor

final class AdvisorSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func test_disabled_is_never_due() {
        XCTAssertFalse(AdvisorScheduler.isDue(enabled: false, intervalMinutes: 10, lastCheckedAt: nil, now: now))
    }

    func test_zero_interval_is_never_due() {
        XCTAssertFalse(AdvisorScheduler.isDue(enabled: true, intervalMinutes: 0, lastCheckedAt: nil, now: now))
    }

    func test_never_checked_is_due() {
        XCTAssertTrue(AdvisorScheduler.isDue(enabled: true, intervalMinutes: 10, lastCheckedAt: nil, now: now))
    }

    func test_due_when_interval_elapsed() {
        XCTAssertTrue(AdvisorScheduler.isDue(enabled: true, intervalMinutes: 10,
            lastCheckedAt: now.addingTimeInterval(-11 * 60), now: now))
    }

    func test_not_due_before_interval() {
        XCTAssertFalse(AdvisorScheduler.isDue(enabled: true, intervalMinutes: 10,
            lastCheckedAt: now.addingTimeInterval(-9 * 60), now: now))
    }
}
