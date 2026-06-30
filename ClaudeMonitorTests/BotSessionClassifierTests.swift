// ClaudeMonitorTests/BotSessionClassifierTests.swift
import XCTest
@testable import ClaudeMonitor

final class BotSessionClassifierTests: XCTestCase {
    private func isBot(_ prompt: String = "기능 추가해줘", brief: Bool = false,
                       tools: [String: Int] = ["Edit": 5, "Bash": 10]) -> Bool {
        BotSessionClassifier.isBot(firstUserPrompt: prompt, briefInjected: brief, toolCounts: tools)
    }

    func test_normal_human_coding_session_is_not_bot() {
        XCTAssertFalse(isBot())
    }

    func test_human_session_with_a_few_subagents_is_not_bot() {
        XCTAssertFalse(isBot(tools: ["Agent": 3, "Edit": 4]))
    }

    func test_security_review_bot_is_bot() {
        XCTAssertTrue(isBot("Review this change for security vulnerabilities.\n\nChanged files: ...",
                            tools: ["Read": 1, "StructuredOutput": 1]))
    }

    func test_brief_injected_orchestration_is_bot() {
        XCTAssertTrue(isBot("Read .claude-brief.md and follow it strictly. Bug #333 ...", brief: true))
    }

    func test_structured_output_run_is_bot() {
        XCTAssertTrue(isBot("Score the following", tools: ["StructuredOutput": 2]))
    }

    func test_heavy_multiagent_orchestration_is_bot() {
        XCTAssertTrue(isBot(tools: ["Agent": 149, "SendMessage": 37, "TeamCreate": 5, "Bash": 700]))
    }

    func test_team_tools_presence_is_bot() {
        XCTAssertTrue(isBot(tools: ["SendMessage": 4, "Edit": 2]))
    }
}
