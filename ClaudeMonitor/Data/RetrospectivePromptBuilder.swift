// ClaudeMonitor/Data/RetrospectivePromptBuilder.swift
import Foundation

/// 창 통계(`WindowSummary`) → `claude -p` 회고 프롬프트.
/// 개선점이 헛소리(platitude)가 되지 않도록 "구체 근거 인용·1~3개·일반론 금지"를 지시한다. (#11)
enum RetrospectivePromptBuilder {
    static func build(summary s: WindowSummary, periodLabel: String) -> String {
        let projects = s.topProjects.map { "\($0.name)(\($0.count))" }.joined(separator: ", ")
        let tools = s.topTools.map { "\($0.name)(\($0.count))" }.joined(separator: ", ")
        let hours = s.busiestHours.map { "\($0)시" }.joined(separator: ", ")
        let testPct = Int((s.testTouchRate * 100).rounded())
        let avgGoals = String(format: "%.1f", s.avgGoalsPerSession)

        return """
        당신은 한 개발자의 AI 코딩 도구(Claude Code) 사용 패턴을 회고해 주는 코치다.
        아래는 \(periodLabel) 동안 이 사용자가 직접 진행한 작업 세션의 집계 통계다.
        (봇/자동화 세션 \(s.botSessions)개는 제외했다.)

        ## 집계 (사람 세션 기준)
        - 세션 수: \(s.humanSessions)
        - 총 목표(프롬프트 의도): \(s.goals)  ·  세션당 평균 \(avgGoals)개
        - 에러 발생: \(s.errors)  ·  중도 중단(interrupt): \(s.interrupts)
        - 테스트 동반 세션 비율: \(testPct)%
        - 총 토큰: \(s.tokens)
        - 많이 만진 프로젝트: \(projects)
        - 많이 쓴 도구: \(tools)
        - 작업이 몰린 시각: \(hours)

        ## 작성 지침
        1. 먼저 이 기간의 **사용 패턴**을 3~5문장으로 관찰해 서술하라. 반드시 위 수치에 근거할 것.
        2. 그다음 **개선점을 1~3개**만 제시하라. 더도 말고.
        3. 각 개선점은 위의 **구체적인 수치/패턴을 근거로 인용**해야 한다
           (예: "세션당 평균 \(avgGoals)개 목표를 다뤄 …", "테스트 동반이 \(testPct)%에 그쳐 …").
        4. "테스트를 더 작성하세요" 같은 **일반론·뻔한 조언은 금지**한다.
           근거 수치를 댈 수 없는 조언이면 쓰지 마라.
        5. 출력은 **한국어**, 마크다운. 군더더기 없이.
        """
    }
}
