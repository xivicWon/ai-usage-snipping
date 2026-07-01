// ClaudeMonitor/Data/AdvisorPromptBuilder.swift
import Foundation

/// 트리거된 조건 + 라이브 신호 → `claude -p` 프롬프트. 순수 함수.
/// 조언은 간결·실행가능해야 하므로 그 가드를 프롬프트에 담는다.
enum AdvisorPromptBuilder {
    static func build(condition: AdvisorCondition, signals: AdvisorSignals) -> String {
        var lines: [String] = []
        lines.append("당신은 Claude Code 사용자의 실시간 코치입니다.")
        lines.append("아래 상황이 감지되었습니다: [\(condition.label)] \(condition.summary)")
        lines.append("")
        lines.append("현재 세션 신호:")
        lines.append("- 누적 토큰: \(signals.totalTokens)")
        lines.append("- 편집한 파일 수: \(signals.filesEditedCount)")
        lines.append("- 도구 에러 수: \(signals.errorCount)")
        if let used = signals.fiveHourPercentUsed {
            lines.append("- 5시간 한도 소진율: \(used)%")
        }
        lines.append("")
        lines.append("""
        이 상황을 벗어나기 위한 조언을 한국어로 작성하세요. 요구사항:
        - 간결하게(150단어 이내), 바로 실행 가능한 3가지 이내의 행동 제안
        - 마크다운으로 '## 상황'과 '## 제안' 두 섹션만
        - 일반론 대신 위 신호에 근거한 구체적 조언
        """)
        return lines.joined(separator: "\n")
    }
}
