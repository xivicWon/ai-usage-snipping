// ClaudeMonitor/Data/NewsScheduler.swift
import Foundation

/// 뉴스 다이제스트 자동 생성 주기.
enum NewsInterval: String, CaseIterable, Identifiable {
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

/// 뉴스 다이제스트를 지금 생성할 때가 됐는지 판정 — 순수 함수.
enum NewsScheduler {
    static func isDue(interval: NewsInterval, lastGeneratedAt: Date?, now: Date) -> Bool {
        guard let secs = interval.seconds else { return false }   // off
        guard let last = lastGeneratedAt else { return true }     // 한 번도 안 함 → 지금
        return now.timeIntervalSince(last) >= secs
    }
}
