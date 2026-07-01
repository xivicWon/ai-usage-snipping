// ClaudeMonitor/Data/NewsDigest.swift
import Foundation

/// 생성된 뉴스 다이제스트 1건. 본문(마크다운 한줄요약) + 근거 스냅샷.
struct NewsDigest: Equatable, Identifiable {
    var id: String
    var generatedAt: Date
    var body: String        // 마크다운 한줄요약 리스트
    var itemCount: Int      // 수집된 원본 항목 수 (근거 스냅샷)
    var sourceCount: Int    // 성공적으로 가져온 소스 수
}
