// ClaudeMonitor/Data/NewsSummaryPromptBuilder.swift
import Foundation

/// 수집한 뉴스 항목들 → `claude -p` 한줄요약 프롬프트. 순수 함수.
/// claude -p 는 웹 접근이 없으므로 제목/출처/링크를 프롬프트에 직접 넣는다.
enum NewsSummaryPromptBuilder {
    /// 항목 목록을 3~5개 한국어 한줄요약을 요청하는 프롬프트로 변환한다.
    static func build(items: [NewsItem]) -> String {
        let list = items.enumerated().map { idx, item -> String in
            let src = item.source.isEmpty ? "" : " (\(item.source))"
            return "\(idx + 1). \(item.title)\(src)"
        }.joined(separator: "\n")

        return """
        당신은 AI/개발 분야 최신 동향을 짧게 정리해 주는 뉴스 큐레이터다.
        아래는 오늘 여러 소스에서 수집한 최신 뉴스 제목 목록이다.

        ## 수집된 뉴스 제목
        \(list)

        ## 작성 지침
        1. 위 목록에서 **가장 중요하고 흥미로운 3~5개**만 골라라. 더도 말고.
        2. 각 항목을 **한 줄 한국어 요약(한줄요약)** 으로 작성하라. 한 문장, 40자 내외.
        3. 형식은 마크다운 리스트("- ...")로, 각 줄에 핵심만. 불릿 하나당 한 뉴스.
        4. 제목을 그대로 번역하지 말고, **왜 중요한지**가 드러나게 요약하라.
        5. 목록에 없는 내용을 지어내지 마라. 출력은 **한국어**, 군더더기 없이.
        6. 앞뒤 인사말·설명 없이 요약 리스트만 출력하라.
        """
    }
}
