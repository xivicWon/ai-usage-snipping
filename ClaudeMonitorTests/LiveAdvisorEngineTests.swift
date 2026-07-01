// ClaudeMonitorTests/LiveAdvisorEngineTests.swift
import XCTest
@testable import ClaudeMonitor

final class LiveAdvisorEngineTests: XCTestCase {
    var store: AdvisorAdviceStore!
    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() {
        super.setUp()
        store = try! AdvisorAdviceStore(path: ":memory:")
    }

    private func makeEngine(generate: @escaping (String) throws -> String) -> LiveAdvisorEngine {
        var clock = t0
        return LiveAdvisorEngine(store: store, generate: generate,
                                 now: { clock },
                                 advanceClock: { clock = clock.addingTimeInterval($0) },
                                 makeId: { "fixed" })
    }

    private func sig(tokens: Int = 0, files: Int = 0, errors: Int = 0, used: Int? = nil) -> AdvisorSignals {
        AdvisorSignals(totalTokens: tokens, filesEditedCount: files, errorCount: errors, fiveHourPercentUsed: used)
    }

    func test_no_trigger_returns_nil_and_does_not_call_generate() {
        var called = false
        let engine = makeEngine { _ in called = true; return "x" }
        let r = engine.check(signals: sig(tokens: 100, files: 1), intervalMinutes: 10)
        XCTAssertNil(r)
        XCTAssertFalse(called)
        XCTAssertEqual(try! store.count(), 0)
    }

    func test_trigger_generates_and_saves_advice() {
        var promptSeen = ""
        let engine = makeEngine { p in promptSeen = p; return "## 조언\n편집을 해보세요" }
        // 막힘: 급증+편집0 연속 2회
        _ = engine.check(signals: sig(tokens: 0, files: 2), intervalMinutes: 10)
        XCTAssertNil(engine.check(signals: sig(tokens: 8_000, files: 2), intervalMinutes: 10))
        let advice = engine.check(signals: sig(tokens: 16_000, files: 2), intervalMinutes: 10)
        XCTAssertNotNil(advice)
        XCTAssertEqual(advice?.body, "## 조언\n편집을 해보세요")
        XCTAssertEqual(advice?.condition, AdvisorCondition.stuck.rawValue)
        XCTAssertTrue(promptSeen.contains(AdvisorCondition.stuck.label))
        XCTAssertEqual(try! store.latest()?.id, "fixed")
    }

    func test_generation_failure_returns_nil_no_save() {
        let engine = makeEngine { _ in throw HeadlessError.failed("boom") }
        _ = engine.check(signals: sig(tokens: 0, files: 2), intervalMinutes: 10)
        _ = engine.check(signals: sig(tokens: 8_000, files: 2), intervalMinutes: 10)
        let advice = engine.check(signals: sig(tokens: 16_000, files: 2), intervalMinutes: 10)
        XCTAssertNil(advice)
        XCTAssertEqual(try! store.count(), 0)
    }
}
