// ClaudeMonitor/Data/RetrospectiveEngine.swift
import Foundation

/// 회고 대상 기간.
enum RetroPeriod: String, CaseIterable, Identifiable {
    case day, threeDays, week
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "최근 1일"
        case .threeDays: return "최근 3일"
        case .week: return "최근 7일"
        }
    }
    var days: Int { self == .day ? 1 : (self == .threeDays ? 3 : 7) }
    func range(now: Date) -> (from: Date, to: Date) {
        (now.addingTimeInterval(-Double(days) * 86400), now)
    }
}

/// 회고 생성 파이프라인 오케스트레이터.
/// 기간 → 세션 피처 조회 → 집계(봇 제외) → 프롬프트 → 생성기(claude -p) → 리포트 저장.
final class RetrospectiveEngine {
    enum GenerateError: Error, Equatable { case noActivity, generationFailed(String) }

    private let featureStore: SessionFeatureStore
    private let reportStore: RetrospectiveReportStore
    private let generate: (String) throws -> String   // 프롬프트 → 회고 본문 (claude -p 주입)
    private let now: () -> Date
    private let makeId: () -> String

    init(featureStore: SessionFeatureStore,
         reportStore: RetrospectiveReportStore,
         generate: @escaping (String) throws -> String,
         now: @escaping () -> Date = Date.init,
         makeId: @escaping () -> String = { UUID().uuidString }) {
        self.featureStore = featureStore
        self.reportStore = reportStore
        self.generate = generate
        self.now = now
        self.makeId = makeId
    }

    /// 회고를 생성·저장하고 반환한다. 활동 없으면 noActivity, 생성 실패면 generationFailed.
    @discardableResult
    func generate(period: RetroPeriod, style: RetroStyle = .standard) throws -> RetrospectiveReport {
        let nowDate = now()
        let (from, to) = period.range(now: nowDate)
        let features = (try? featureStore.features(from: from, to: to)) ?? []
        let summary = RetrospectiveAggregator.summarize(features)
        guard summary.humanSessions > 0 else { throw GenerateError.noActivity }

        let prompt = RetrospectivePromptBuilder.build(summary: summary, periodLabel: period.label, style: style)
        let body: String
        do {
            body = try generate(prompt)
        } catch let e as GenerateError {
            throw e
        } catch {
            throw GenerateError.generationFailed("\(error)")
        }

        let report = RetrospectiveReport(
            id: makeId(), periodLabel: period.label, from: from, to: to,
            generatedAt: nowDate, body: body,
            humanSessions: summary.humanSessions, botSessions: summary.botSessions,
            style: style)
        try reportStore.save(report)
        return report
    }
}
