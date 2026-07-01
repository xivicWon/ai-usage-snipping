// ClaudeMonitorTests/RSSFeedParserTests.swift
import XCTest
@testable import ClaudeMonitor

final class RSSFeedParserTests: XCTestCase {

    private let rss = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Example AI Blog</title>
        <item>
          <title>Claude 3.5 출시</title>
          <link>https://example.com/claude-35</link>
          <pubDate>Mon, 06 Sep 2021 16:20:00 +0000</pubDate>
        </item>
        <item>
          <title><![CDATA[New model & benchmarks]]></title>
          <link>https://example.com/bench</link>
          <pubDate>Tue, 07 Sep 2021 10:00:00 +0000</pubDate>
        </item>
      </channel>
    </rss>
    """

    private let atom = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Atom Feed</title>
      <entry>
        <title>Atom entry one</title>
        <link href="https://example.com/atom1" rel="alternate"/>
        <updated>2023-01-15T12:30:00Z</updated>
      </entry>
    </feed>
    """

    func test_parses_rss_items() {
        let items = RSSFeedParser.parse(rss)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Claude 3.5 출시")
        XCTAssertEqual(items[0].link, "https://example.com/claude-35")
    }

    func test_parses_cdata_title() {
        let items = RSSFeedParser.parse(rss)
        XCTAssertEqual(items[1].title, "New model & benchmarks")
    }

    func test_parses_pubdate_rfc822() {
        let items = RSSFeedParser.parse(rss)
        XCTAssertNotNil(items[0].pubDate)
        // 2021-09-06 16:20:00 UTC
        XCTAssertEqual(items[0].pubDate, Date(timeIntervalSince1970: 1_630_945_200))
    }

    func test_carries_source_name() {
        let items = RSSFeedParser.parse(rss, source: "Anthropic")
        XCTAssertEqual(items[0].source, "Anthropic")
    }

    func test_parses_atom_entries_with_link_attribute() {
        let items = RSSFeedParser.parse(atom)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Atom entry one")
        XCTAssertEqual(items[0].link, "https://example.com/atom1")
        XCTAssertNotNil(items[0].pubDate)
    }

    func test_empty_or_garbage_returns_empty() {
        XCTAssertTrue(RSSFeedParser.parse("").isEmpty)
        XCTAssertTrue(RSSFeedParser.parse("not xml at all <<<").isEmpty)
        XCTAssertTrue(RSSFeedParser.parse("<rss><channel></channel></rss>").isEmpty)
    }

    func test_skips_items_without_title() {
        let xml = """
        <rss><channel>
          <item><link>https://x.com/a</link></item>
          <item><title>Has title</title><link>https://x.com/b</link></item>
        </channel></rss>
        """
        let items = RSSFeedParser.parse(xml)
        XCTAssertEqual(items.map(\.title), ["Has title"])
    }
}
