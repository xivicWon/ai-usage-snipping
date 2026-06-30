// ClaudeMonitor/Data/BotSessionClassifier.swift
import Foundation

/// 세션이 사람이 직접 한 작업인지, 자동화/봇(오케스트레이션·리뷰봇·구조화출력 등)인지 판정.
/// 회고는 사람 작업에 집중해야 하므로, 봇 세션은 플래그해 집계에서 기본 제외한다.
enum BotSessionClassifier {

    /// 봇/메타 세션이면 true.
    /// - firstUserPrompt: 첫 실제 사용자 프롬프트(스킬 주입 제외)
    /// - briefInjected: `.claude-brief.md` 등 자동 브리프 주입 정황
    /// - toolCounts: 도구 사용 횟수
    static func isBot(firstUserPrompt: String, briefInjected: Bool, toolCounts: [String: Int]) -> Bool {
        // ① 자동 브리프 주입(.claude-brief) 정황
        if briefInjected { return true }

        // ② 리뷰/구조화 출력 봇 — 프롬프트 템플릿
        let p = firstUserPrompt.lowercased()
        if p.hasPrefix("review this change")
            || p.contains("security vulnerabilit")
            || p.contains(".claude-brief") { return true }

        // ③ 구조화 출력(judge/review 자동 실행)
        if (toolCounts["StructuredOutput"] ?? 0) > 0 { return true }

        // ④ 멀티에이전트 오케스트레이션 — 팀 도구는 자동화 전용
        if (toolCounts["TeamCreate"] ?? 0) > 0 || (toolCounts["SendMessage"] ?? 0) > 0 { return true }

        // ⑤ 서브에이전트 과다 — 사람은 보통 소수만 띄움
        if (toolCounts["Agent"] ?? 0) >= 10 { return true }

        return false
    }
}
