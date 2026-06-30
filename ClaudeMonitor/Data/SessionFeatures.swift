// ClaudeMonitor/Data/SessionFeatures.swift
import Foundation

/// 한 세션(트랜스크립트 파일 1개)에서 추출한 파생 신호.
/// 원문은 저장하지 않고 이 작은 피처만 축적한다 — 회고 집계의 입력.
struct SessionFeatures: Equatable {
    var sessionId: String
    var source: String              // "claude" | "codex"
    var projectPath: String
    /// 사용자 의도 프롬프트 수 (스킬 주입·도구결과·중단 마커 제외)
    var goalCount: Int
    var toolCounts: [String: Int]
    var filesEdited: [String]
    var testTouched: Bool
    var errorCount: Int              // tool_result is_error 수
    var interruptCount: Int          // "[Request interrupted by user]" 마커 수
    var totalTokens: Int
    var startedAt: Date?
    var endedAt: Date?
    /// 자동화/봇 세션 여부 — 회고 집계에서 기본 제외. [[bot-session-classifier]]
    var isBot: Bool
}
