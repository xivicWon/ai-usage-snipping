// ClaudeMonitorTests/NewsDigestEngineTests.swift
import XCTest
@testable import ClaudeMonitor

final class NewsDigestEngineTests: XCTestCase {
    var store: NewsDigestStore!
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() {
        super.setUp()
        store = try! NewsDigestStore(path: ":memory:")
    }

    private func rss(_ title: String, pub: String = "Mon, 06 Sep 2021 16:20:00 +0000") -> String {
        """
        <rss><channel><item>
          <title>\(title)</title><link>https://x.com/\(title)</link><pubDate>\(pub)</pubDate>
        </item></channel></rss>
        """
    }

    private func makeEngine(sources: [NewsSource],
                            fetch: @escaping (NewsSource) -> String?,
                            generate: @escaping (String) throws -> String) -> NewsDigestEngine {
        NewsDigestEngine(store: store, sources: sources, fetch: fetch, generate: generate,
                         now: { self.now }, makeId: { "fixed-id" })
    }

    func test_throws_noItems_when_all_fetches_fail() {
        let s = [NewsSource(name: "A", url: "https://a.com")]
        let engine = makeEngine(sources: s, fetch: { _ in nil }, generate: { _ in "x" })
        XCTAssertThrowsError(try engine.generate()) {
            XCTAssertEqual($0 as? NewsDigestEngine.GenerateError, .noItems)
        }
    }

    func test_generates_and_saves_digest() throws {
        let s = [NewsSource(name: "A", url: "https://a.com")]
        let engine = makeEngine(sources: s, fetch: { _ in self.rss("Big AI news") },
                                generate: { _ in "- 오늘의 한줄요약" })
        let digest = try engine.generate()
        XCTAssertEqual(digest.body, "- 오늘의 한줄요약")
        XCTAssertEqual(digest.id, "fixed-id")
        XCTAssertEqual(digest.generatedAt, now)
        XCTAssertEqual(digest.itemCount, 1)
        XCTAssertEqual(digest.sourceCount, 1)
        XCTAssertEqual(try store.latest(), digest)
    }

    func test_prompt_receives_collected_titles() throws {
        let s = [NewsSource(name: "A", url: "https://a.com")]
        var captured = ""
        let engine = makeEngine(sources: s, fetch: { _ in self.rss("Unique Headline XYZ") },
                                generate: { p in captured = p; return "본문" })
        _ = try engine.generate()
        XCTAssertTrue(captured.contains("Unique Headline XYZ"))
        XCTAssertTrue(captured.contains("한줄요약"))
    }

    func test_skips_failing_sources_but_uses_working_ones() throws {
        let sources = [
            NewsSource(name: "Bad", url: "https://bad.com"),
            NewsSource(name: "Good", url: "https://good.com"),
        ]
        let engine = makeEngine(sources: sources,
                                fetch: { $0.name == "Good" ? self.rss("From good") : nil },
                                generate: { _ in "요약" })
        let digest = try engine.generate()
        XCTAssertEqual(digest.sourceCount, 1)
        XCTAssertEqual(digest.itemCount, 1)
    }

    func test_propagates_generation_failure() {
        let s = [NewsSource(name: "A", url: "https://a.com")]
        let engine = makeEngine(sources: s, fetch: { _ in self.rss("news") },
                                generate: { _ in throw NewsDigestEngine.GenerateError.generationFailed("boom") })
        XCTAssertThrowsError(try engine.generate()) {
            XCTAssertEqual($0 as? NewsDigestEngine.GenerateError, .generationFailed("boom"))
        }
    }

    func test_respects_maxItems_cap() throws {
        let s = [NewsSource(name: "A", url: "https://a.com")]
        // 하나의 피드에 여러 item — pubDate 최신순으로 상한 적용
        let manyItems = (0..<10).map { i in
            "<item><title>T\(i)</title><link>https://x/\(i)</link></item>"
        }.joined()
        let xml = "<rss><channel>\(manyItems)</channel></rss>"
        var captured = ""
        let engine = NewsDigestEngine(store: store, sources: s, fetch: { _ in xml },
                                      generate: { p in captured = p; return "ok" },
                                      maxItems: 3, now: { self.now }, makeId: { "id" })
        let digest = try engine.generate()
        XCTAssertEqual(digest.itemCount, 10)          // 원본은 모두 집계
        // 프롬프트에는 3개만 (4번째는 제외)
        XCTAssertTrue(captured.contains("T0"))
        XCTAssertFalse(captured.contains("T4"))
    }
}
