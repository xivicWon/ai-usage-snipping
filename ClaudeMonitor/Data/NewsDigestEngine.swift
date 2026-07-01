// ClaudeMonitor/Data/NewsDigestEngine.swift
import Foundation

/// 뉴스 다이제스트 생성 파이프라인 오케스트레이터.
/// 소스 fetch(주입) → RSS 파싱 → 프롬프트 → 생성기(claude -p, 주입) → 저장.
final class NewsDigestEngine {
    enum GenerateError: Error, Equatable { case noItems, generationFailed(String) }

    private let store: NewsDigestStore
    private let sources: [NewsSource]
    private let fetch: (NewsSource) -> String?      // 소스 → 피드 XML (실패 시 nil, 조용히 스킵)
    private let summarize: (String) throws -> String // 프롬프트 → 요약 본문 (claude -p 주입)
    private let maxItems: Int
    private let now: () -> Date
    private let makeId: () -> String

    init(store: NewsDigestStore,
         sources: [NewsSource] = NewsSource.defaults,
         fetch: @escaping (NewsSource) -> String?,
         generate: @escaping (String) throws -> String,
         maxItems: Int = 30,
         now: @escaping () -> Date = Date.init,
         makeId: @escaping () -> String = { UUID().uuidString }) {
        self.store = store
        self.sources = sources
        self.fetch = fetch
        self.summarize = generate
        self.maxItems = maxItems
        self.now = now
        self.makeId = makeId
    }

    /// 다이제스트를 생성·저장하고 반환한다. 수집 항목 없으면 noItems, 생성 실패면 generationFailed.
    @discardableResult
    func generate() throws -> NewsDigest {
        var items: [NewsItem] = []
        var okSources = 0
        for source in sources {
            guard let xml = fetch(source) else { continue }   // 실패는 조용히 스킵
            let parsed = RSSFeedParser.parse(xml, source: source.name)
            if !parsed.isEmpty { okSources += 1 }
            items.append(contentsOf: parsed)
        }
        guard !items.isEmpty else { throw GenerateError.noItems }

        // 최신순 정렬 후 상한 적용 (pubDate 없는 항목은 뒤로)
        let sorted = items.sorted {
            ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast)
        }
        let selected = Array(sorted.prefix(maxItems))

        let prompt = NewsSummaryPromptBuilder.build(items: selected)
        let body: String
        do {
            body = try summarize(prompt)
        } catch let e as GenerateError {
            throw e
        } catch {
            throw GenerateError.generationFailed("\(error)")
        }

        let digest = NewsDigest(
            id: makeId(), generatedAt: now(), body: body,
            itemCount: items.count, sourceCount: okSources)
        try store.save(digest)
        return digest
    }
}

/// 실제 URLSession 동기 fetch 어댑터. (통합 계층 — 단위테스트는 fetch 를 주입해 오프라인)
enum URLSessionFeedFetcher {
    /// 소스 URL 에서 피드 텍스트를 동기적으로 가져온다. 실패/타임아웃은 nil.
    static func fetch(_ source: NewsSource, timeout: TimeInterval = 15) -> String? {
        guard let url = URL(string: source.url) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Mozilla/5.0 (compatible; ClaudeMonitor)", forHTTPHeaderField: "User-Agent")

        let sem = DispatchSemaphore(value: 0)
        var result: String?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { sem.signal() }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return }
            if let data, let text = String(data: data, encoding: .utf8) { result = text }
        }
        task.resume()
        if sem.wait(timeout: .now() + timeout + 2) == .timedOut {
            task.cancel()
            return nil
        }
        return result
    }
}
