// ClaudeMonitor/Data/NewsItem.swift
import Foundation

/// 뉴스 소스(RSS/Atom)에서 추출한 항목 1건.
struct NewsItem: Equatable {
    var title: String
    var link: String
    var pubDate: Date?
    var source: String   // 출처 이름 (예: "Anthropic")

    init(title: String, link: String, pubDate: Date? = nil, source: String = "") {
        self.title = title
        self.link = link
        self.pubDate = pubDate
        self.source = source
    }
}

/// 뉴스 소스 정의 — 이름 + 피드 URL.
struct NewsSource: Equatable, Identifiable {
    var name: String
    var url: String
    var id: String { url }

    /// v1 기본 소스 — AI 블로그/뉴스 RSS. 실패는 조용히 스킵되므로 넉넉히 둔다.
    static let defaults: [NewsSource] = [
        NewsSource(name: "Anthropic", url: "https://www.anthropic.com/rss.xml"),
        NewsSource(name: "OpenAI", url: "https://openai.com/blog/rss.xml"),
        NewsSource(name: "Google AI", url: "https://blog.google/technology/ai/rss/"),
        NewsSource(name: "Hugging Face", url: "https://huggingface.co/blog/feed.xml"),
        NewsSource(name: "Hacker News (AI)", url: "https://hnrss.org/newest?q=AI+OR+LLM+OR+Claude+OR+GPT&count=20"),
    ]
}
