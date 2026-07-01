// ClaudeMonitorTests/AdvisorDetectorTests.swift
import XCTest
@testable import ClaudeMonitor

/// 라이브 어드바이저의 심장 — 순수 감지 규칙. 반복 판정(연속 K회)·쿨다운·이중발사 방지.
final class AdvisorDetectorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)
    private let config = AdvisorConfig()   // K=2, cooldown 30분, stuckTokenDelta 5000, ETA 30분

    /// 매 체크를 10분 간격으로 진행하는 헬퍼.
    private func step(_ state: AdvisorState, _ signals: AdvisorSignals, minutes: Double)
        -> (state: AdvisorState, triggered: AdvisorCondition?) {
        let now = (state.previousAt ?? t0).addingTimeInterval(minutes * 60)
        return AdvisorDetector.evaluate(current: signals, now: now, state: state, config: config)
    }

    private func sig(tokens: Int = 0, files: Int = 0, errors: Int = 0, used: Int? = nil) -> AdvisorSignals {
        AdvisorSignals(totalTokens: tokens, filesEditedCount: files, errorCount: errors, fiveHourPercentUsed: used)
    }

    // MARK: - 첫 체크는 기준선만 잡고 절대 트리거하지 않는다

    func test_first_check_never_triggers() {
        let (state, trig) = AdvisorDetector.evaluate(
            current: sig(tokens: 100_000, files: 0), now: t0, state: AdvisorState(), config: config)
        XCTAssertNil(trig)
        XCTAssertEqual(state.previous, sig(tokens: 100_000, files: 0))
    }

    // MARK: - 막힘 (mandatory): 토큰 급증 + 편집 0 이 연속 2회

    func test_stuck_needs_two_consecutive_checks() {
        var st = AdvisorState()
        (st, _) = step(st, sig(tokens: 0, files: 3), minutes: 10)         // baseline
        var trig: AdvisorCondition?
        (st, trig) = step(st, sig(tokens: 8_000, files: 3), minutes: 10)  // 1회 막힘 → 아직
        XCTAssertNil(trig)
        (st, trig) = step(st, sig(tokens: 16_000, files: 3), minutes: 10) // 2회 연속 → 발사
        XCTAssertEqual(trig, .stuck)
    }

    func test_stuck_resets_when_edit_happens() {
        var st = AdvisorState()
        (st, _) = step(st, sig(tokens: 0, files: 3), minutes: 10)
        var trig: AdvisorCondition?
        (st, trig) = step(st, sig(tokens: 8_000, files: 3), minutes: 10)  // 막힘 1회
        XCTAssertNil(trig)
        (st, trig) = step(st, sig(tokens: 16_000, files: 4), minutes: 10) // 편집 발생 → 스트릭 리셋
        XCTAssertNil(trig)
        (st, trig) = step(st, sig(tokens: 24_000, files: 4), minutes: 10) // 다시 1회
        XCTAssertNil(trig)
    }

    func test_small_token_growth_is_not_stuck() {
        var st = AdvisorState()
        (st, _) = step(st, sig(tokens: 0, files: 1), minutes: 10)
        var trig: AdvisorCondition?
        (st, trig) = step(st, sig(tokens: 1_000, files: 1), minutes: 10)  // < 5000 임계
        XCTAssertNil(trig)
        (st, trig) = step(st, sig(tokens: 2_000, files: 1), minutes: 10)
        XCTAssertNil(trig)
    }

    // MARK: - 에러 반복: errorCount 연속 증가 2회

    func test_error_repeat_two_consecutive() {
        var st = AdvisorState()
        (st, _) = step(st, sig(errors: 1), minutes: 10)
        var trig: AdvisorCondition?
        (st, trig) = step(st, sig(errors: 2), minutes: 10)   // +1 (1회)
        XCTAssertNil(trig)
        (st, trig) = step(st, sig(errors: 4), minutes: 10)   // +2 (2회 연속) → 발사
        XCTAssertEqual(trig, .errorRepeat)
    }

    func test_error_flat_does_not_trigger() {
        var st = AdvisorState()
        (st, _) = step(st, sig(errors: 5), minutes: 10)
        var trig: AdvisorCondition?
        (st, trig) = step(st, sig(errors: 5), minutes: 10)
        XCTAssertNil(trig)
        (st, trig) = step(st, sig(errors: 5), minutes: 10)
        XCTAssertNil(trig)
    }

    // MARK: - 한도 임박: 5h 소진 ETA < 30분 (기울기 기반)

    func test_rate_limit_imminent_by_slope() {
        var st = AdvisorState()
        // 10분에 +10% 소진 → slope 1%/분. used 85 → ETA (100-85)/1 = 15분 < 30 → 임박
        (st, _) = step(st, sig(used: 75), minutes: 10)
        var trig: AdvisorCondition?
        (st, trig) = step(st, sig(used: 85), minutes: 10)   // 1회 임박
        XCTAssertNil(trig)
        (st, trig) = step(st, sig(used: 95), minutes: 10)   // 2회 연속 → 발사
        XCTAssertEqual(trig, .rateLimitImminent)
    }

    func test_rate_limit_slow_slope_not_imminent() {
        var st = AdvisorState()
        // 10분에 +1% → slope 0.1%/분, used 50 → ETA 500분 → 아님
        (st, _) = step(st, sig(used: 49), minutes: 10)
        var trig: AdvisorCondition?
        (st, trig) = step(st, sig(used: 50), minutes: 10)
        XCTAssertNil(trig)
        (st, trig) = step(st, sig(used: 51), minutes: 10)
        XCTAssertNil(trig)
    }

    // MARK: - 쿨다운: 발사 직후 30분 내 재발사 금지

    func test_cooldown_prevents_double_fire() {
        var st = AdvisorState()
        (st, _) = step(st, sig(tokens: 0, files: 2), minutes: 10)
        var trig: AdvisorCondition?
        (st, trig) = step(st, sig(tokens: 8_000, files: 2), minutes: 10)
        XCTAssertNil(trig)
        (st, trig) = step(st, sig(tokens: 16_000, files: 2), minutes: 10)  // 발사
        XCTAssertEqual(trig, .stuck)
        // 10분 뒤 여전히 막힘이지만 쿨다운(30분) 내 → 발사 금지
        (st, trig) = step(st, sig(tokens: 24_000, files: 2), minutes: 10)
        XCTAssertNil(trig)
        (st, trig) = step(st, sig(tokens: 32_000, files: 2), minutes: 10)
        XCTAssertNil(trig)
    }

    func test_fires_again_after_cooldown_elapses() {
        var st = AdvisorState()
        (st, _) = step(st, sig(tokens: 0, files: 2), minutes: 10)
        var trig: AdvisorCondition?
        (st, trig) = step(st, sig(tokens: 8_000, files: 2), minutes: 10)
        (st, trig) = step(st, sig(tokens: 16_000, files: 2), minutes: 10)  // 발사 (t=30m)
        XCTAssertEqual(trig, .stuck)
        // 40분 경과(쿨다운 30분 초과) 후 다시 막힘 2회 → 재발사
        (st, trig) = step(st, sig(tokens: 24_000, files: 2), minutes: 40)  // 1회
        XCTAssertNil(trig)
        (st, trig) = step(st, sig(tokens: 32_000, files: 2), minutes: 10)  // 2회 연속 → 발사
        XCTAssertEqual(trig, .stuck)
    }
}
