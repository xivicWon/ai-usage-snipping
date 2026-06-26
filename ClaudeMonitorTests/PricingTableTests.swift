// ClaudeMonitorTests/PricingTableTests.swift
import XCTest
@testable import ClaudeMonitor

final class PricingTableTests: XCTestCase {

    func test_opus_1M_input_costs_15_dollars() {
        let cost = PricingTable.cost(
            model: "claude-opus-4-8",
            input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0
        )
        XCTAssertEqual(cost, 15.0, accuracy: 0.0001)
    }

    func test_sonnet_1M_output_costs_15_dollars() {
        let cost = PricingTable.cost(
            model: "claude-sonnet-4-6",
            input: 0, output: 1_000_000, cacheRead: 0, cacheWrite: 0
        )
        XCTAssertEqual(cost, 15.0, accuracy: 0.0001)
    }

    func test_haiku_mixed_100k_input_50k_output() {
        // input: 100k * (0.80/1M) = $0.08, output: 50k * (4.0/1M) = $0.20
        let cost = PricingTable.cost(
            model: "claude-haiku-4-5",
            input: 100_000, output: 50_000, cacheRead: 0, cacheWrite: 0
        )
        XCTAssertEqual(cost, 0.28, accuracy: 0.0001)
    }

    func test_sonnet_cache_read_1M_costs_30_cents() {
        let cost = PricingTable.cost(
            model: "claude-sonnet-4-6",
            input: 0, output: 0, cacheRead: 1_000_000, cacheWrite: 0
        )
        XCTAssertEqual(cost, 0.30, accuracy: 0.0001)
    }

    func test_opus_cache_write_1M_costs_18_75() {
        let cost = PricingTable.cost(
            model: "claude-opus-4-8",
            input: 0, output: 0, cacheRead: 0, cacheWrite: 1_000_000
        )
        XCTAssertEqual(cost, 18.75, accuracy: 0.0001)
    }

    func test_unknown_model_returns_nonzero_cost() {
        let cost = PricingTable.cost(
            model: "claude-future-model-99",
            input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0
        )
        XCTAssertGreaterThan(cost, 0)
    }

    func test_all_zero_tokens_returns_zero() {
        let cost = PricingTable.cost(
            model: "claude-sonnet-4-6",
            input: 0, output: 0, cacheRead: 0, cacheWrite: 0
        )
        XCTAssertEqual(cost, 0.0)
    }
}
