// ClaudeMonitorTests/NewsSummaryPromptBuilderTests.swift
import XCTest
@testable import ClaudeMonitor

final class NewsSummaryPromptBuilderTests: XCTestCase {
    private let items = [
        NewsItem(title: "Claude 3.5 Sonnet released", link: "https://a.com/1", source: "Anthropic"),
        NewsItem(title: "GPT-5 rumors swirl", link: "https://a.com/2", source: "Hacker News"),
        NewsItem(title: "Open weights model beats benchmark", link: "https://a.com/3", source: "Hugging Face"),
    ]

    private func build() -> String { NewsSummaryPromptBuilder.build(items: items) }

    func test_includes_item_titles() {
        let p = build()
        XCTAssertTrue(p.contains("Claude 3.5 Sonnet released"))
        XCTAssertTrue(p.contains("GPT-5 rumors swirl"))
    }

    func test_includes_source_names() {
        XCTAssertTrue(build().contains("Anthropic"))
    }

    func test_requests_one_line_korean_summaries() {
        let p = build()
        XCTAssertTrue(p.contains("한줄요약"))
        XCTAssertTrue(p.contains("한국어"))
    }

    func test_requests_three_to_five() {
        XCTAssertTrue(build().contains("3~5"))
    }

    func test_forbids_hallucination() {
        XCTAssertTrue(build().contains("지어내지"))
    }
}
