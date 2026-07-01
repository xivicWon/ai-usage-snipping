// ClaudeMonitorTests/AdvisorPromptBuilderTests.swift
import XCTest
@testable import ClaudeMonitor

final class AdvisorPromptBuilderTests: XCTestCase {
    func test_prompt_mentions_condition_and_signals() {
        let signals = AdvisorSignals(totalTokens: 50_000, filesEditedCount: 2, errorCount: 5, fiveHourPercentUsed: 92)
        let prompt = AdvisorPromptBuilder.build(condition: .stuck, signals: signals)
        XCTAssertTrue(prompt.contains(AdvisorCondition.stuck.label))
        XCTAssertTrue(prompt.contains("50000") || prompt.contains("50,000"))
        // 조언은 간결·실행가능해야 함 — 프롬프트가 그 가드를 담는다
        XCTAssertTrue(prompt.contains("간결") || prompt.contains("조언"))
    }

    func test_rate_limit_prompt_includes_usage() {
        let signals = AdvisorSignals(totalTokens: 0, filesEditedCount: 0, errorCount: 0, fiveHourPercentUsed: 92)
        let prompt = AdvisorPromptBuilder.build(condition: .rateLimitImminent, signals: signals)
        XCTAssertTrue(prompt.contains("92"))
    }
}
