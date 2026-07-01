// ClaudeMonitor/Data/RetrospectiveReport.swift
import Foundation

/// 생성된 회고 1건. 본문(마크다운) + 근거 지표 스냅샷.
struct RetrospectiveReport: Equatable, Identifiable {
    var id: String
    var periodLabel: String      // "최근 7일" 등
    var from: Date
    var to: Date
    var generatedAt: Date
    var body: String             // 마크다운
    var humanSessions: Int       // 근거 스냅샷
    var botSessions: Int
    var style: RetroStyle = .standard   // 회고 유형 (기본/갱생)
}
