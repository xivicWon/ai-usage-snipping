// ClaudeMonitor/Data/RSSFeedParser.swift
import Foundation

/// RSS 2.0 / Atom 피드 XML → NewsItem 목록. 의존성 없이 Foundation XMLParser 사용.
/// 순수 함수(파싱만) — 네트워크는 엔진 계층에서 주입.
enum RSSFeedParser {
    /// 피드 XML 문자열을 파싱한다. 실패/빈 피드는 빈 배열.
    static func parse(_ xml: String, source: String = "") -> [NewsItem] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let delegate = FeedDelegate(source: source)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }
}

/// XMLParser 델리게이트 — RSS `<item>` 과 Atom `<entry>` 를 모두 처리.
private final class FeedDelegate: NSObject, XMLParserDelegate {
    private(set) var items: [NewsItem] = []
    private let source: String

    private var inEntry = false           // item 또는 entry 내부인지
    private var currentElement = ""
    private var title = ""
    private var link = ""
    private var dateText = ""

    init(source: String) { self.source = source }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        currentElement = name
        if name == "item" || name == "entry" {
            inEntry = true
            title = ""; link = ""; dateText = ""
        } else if inEntry && name == "link" {
            // Atom: <link href="..."/> — 텍스트가 없으므로 속성에서 취득
            if let href = attributeDict["href"], !href.isEmpty {
                // rel="alternate" 또는 rel 없음을 우선(대체 링크). self 는 무시.
                if attributeDict["rel"] == nil || attributeDict["rel"] == "alternate" {
                    link = href
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inEntry else { return }
        switch currentElement {
        case "title": title += string
        case "link": link += string
        case "pubdate", "published", "updated", "dc:date", "date": dateText += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard inEntry, let s = String(data: CDATABlock, encoding: .utf8) else { return }
        switch currentElement {
        case "title": title += s
        case "link": link += s
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if name == "item" || name == "entry" {
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let l = link.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                items.append(NewsItem(title: t, link: l,
                                      pubDate: Self.parseDate(dateText), source: source))
            }
            inEntry = false
        }
        currentElement = ""
    }

    /// RFC822(RSS) 와 ISO8601(Atom) 을 모두 시도.
    static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let d = rfc822.date(from: s) { return d }
        if let d = iso8601.date(from: s) { return d }
        if let d = iso8601NoFractional.date(from: s) { return d }
        return nil
    }

    private static let rfc822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601NoFractional = ISO8601DateFormatter()
}
