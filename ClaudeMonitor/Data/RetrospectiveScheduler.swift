// ClaudeMonitor/Data/RetrospectiveScheduler.swift
import Foundation

/// 회고 자동 생성 주기. period(분석 창)와 별개로 "얼마나 자주 생성하나"를 정한다.
enum RetroInterval: String, CaseIterable, Identifiable {
    case off, daily, every3Days, weekly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "끔"
        case .daily: return "매일"
        case .every3Days: return "3일"
        case .weekly: return "매주"
        }
    }
    /// 이 주기가 분석할 창(period). off면 nil.
    var period: RetroPeriod? {
        switch self {
        case .off: return nil
        case .daily: return .day
        case .every3Days: return .threeDays
        case .weekly: return .week
        }
    }
    /// 생성 간격(초). off면 nil.
    var seconds: TimeInterval? {
        switch self {
        case .off: return nil
        case .daily: return 86_400
        case .every3Days: return 3 * 86_400
        case .weekly: return 7 * 86_400
        }
    }
}

/// 회고를 지금 생성할 때가 됐는지 판정 — 순수 함수.
enum RetrospectiveScheduler {
    static func isDue(interval: RetroInterval, lastGeneratedAt: Date?, now: Date) -> Bool {
        guard let secs = interval.seconds else { return false }   // off
        guard let last = lastGeneratedAt else { return true }     // 한 번도 안 함 → 지금
        return now.timeIntervalSince(last) >= secs
    }
}
