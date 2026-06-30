// ClaudeMonitor/Data/RetrospectiveAggregator.swift
import Foundation

struct NamedCount: Equatable { let name: String; let count: Int }

/// 한 기간의 세션 피처를 회고용 압축 통계로 환원한 결과.
/// 봇/메타 세션은 "어떻게 일하는가" 집계에서 제외하고 개수만 따로 보고한다.
struct WindowSummary: Equatable {
    var humanSessions: Int
    var botSessions: Int
    var goals: Int
    var tokens: Int
    var errors: Int
    var interrupts: Int
    var avgGoalsPerSession: Double
    var testTouchRate: Double          // 테스트 동반 사람 세션 비율 (0~1)
    var topProjects: [NamedCount]      // 세션 수 상위
    var topTools: [NamedCount]         // 도구 사용 합계 상위
    var busiestHours: [Int]            // 세션 시작이 많은 시각(0~23) 상위

    static let empty = WindowSummary(
        humanSessions: 0, botSessions: 0, goals: 0, tokens: 0, errors: 0, interrupts: 0,
        avgGoalsPerSession: 0, testTouchRate: 0, topProjects: [], topTools: [], busiestHours: [])
}

/// 회고 입력 통계 산출 — 순수 함수.
enum RetrospectiveAggregator {
    static func summarize(_ features: [SessionFeatures],
                          topN: Int = 5,
                          calendar: Calendar = .current) -> WindowSummary {
        let human = features.filter { !$0.isBot }
        let bots = features.count - human.count
        guard !human.isEmpty else {
            var s = WindowSummary.empty; s.botSessions = bots; return s
        }

        let goals = human.reduce(0) { $0 + $1.goalCount }
        let tokens = human.reduce(0) { $0 + $1.totalTokens }
        let errors = human.reduce(0) { $0 + $1.errorCount }
        let interrupts = human.reduce(0) { $0 + $1.interruptCount }
        let testCount = human.filter { $0.testTouched }.count

        // 프로젝트별 세션 수
        var projCounts: [String: Int] = [:]
        for f in human {
            let name = URL(fileURLWithPath: f.projectPath).lastPathComponent
            projCounts[name, default: 0] += 1
        }
        // 도구 사용 합계
        var toolTotals: [String: Int] = [:]
        for f in human { for (k, v) in f.toolCounts { toolTotals[k, default: 0] += v } }
        // 시작 시각대
        var hourCounts: [Int: Int] = [:]
        for f in human {
            guard let d = f.startedAt else { continue }
            hourCounts[calendar.component(.hour, from: d), default: 0] += 1
        }

        return WindowSummary(
            humanSessions: human.count,
            botSessions: bots,
            goals: goals, tokens: tokens, errors: errors, interrupts: interrupts,
            avgGoalsPerSession: Double(goals) / Double(human.count),
            testTouchRate: Double(testCount) / Double(human.count),
            topProjects: topNamed(projCounts, topN),
            topTools: topNamed(toolTotals, topN),
            busiestHours: hourCounts.sorted { ($0.value, -$0.key) > ($1.value, -$1.key) }
                .prefix(3).map(\.key)
        )
    }

    /// count 내림차순, 동수면 이름 오름차순으로 상위 N개.
    private static func topNamed(_ dict: [String: Int], _ n: Int) -> [NamedCount] {
        dict.sorted { a, b in a.value != b.value ? a.value > b.value : a.key < b.key }
            .prefix(n).map { NamedCount(name: $0.key, count: $0.value) }
    }
}
