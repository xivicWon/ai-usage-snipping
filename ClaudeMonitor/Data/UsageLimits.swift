// ClaudeMonitor/Data/UsageLimits.swift
import Foundation
import Combine

/// User-configured settings. Stored in UserDefaults so they survive restarts.
final class UsageLimits: ObservableObject {
    static let shared = UsageLimits()

    private let defaults = UserDefaults.standard

    /// Claude account email — entered manually since Anthropic has no public profile API.
    @Published var accountEmail: String {
        didSet { defaults.set(accountEmail, forKey: "account_email") }
    }
    /// Max tokens allowed in the 5-hour rolling window. 0 = not set.
    @Published var windowLimitTokens: Int {
        didSet { defaults.set(windowLimitTokens, forKey: "limit_window_tokens") }
    }
    /// Max tokens allowed per week. 0 = not set.
    @Published var weeklyLimitTokens: Int {
        didSet { defaults.set(weeklyLimitTokens, forKey: "limit_weekly_tokens") }
    }
    @Published var codexHomePath: String {
        didSet {
            if codexHomePath.isEmpty {
                defaults.removeObject(forKey: "codex_home_path")
            } else {
                defaults.set(codexHomePath, forKey: "codex_home_path")
            }
        }
    }
    /// 메뉴바에서 Claude 섹션 표시 여부. 기본 true.
    @Published var claudeEnabled: Bool {
        didSet { defaults.set(claudeEnabled, forKey: "claude_enabled") }
    }
    /// 메뉴바에서 Codex 섹션 표시 여부. 기본 true.
    @Published var codexEnabled: Bool {
        didSet { defaults.set(codexEnabled, forKey: "codex_enabled") }
    }

    // MARK: - 토큰 처리율 게이지 단계 임계값 (분당 input+output 토큰)
    // delta < lv1 → 0(유휴), < lv2 → 1(기본), < lv3 → 2(많음), 그 이상 → 3(폭발적)
    static let defaultRateLevel1 = 1_000   // ≈유휴 경계
    static let defaultRateLevel2 = 9_000   // ≈중앙값
    static let defaultRateLevel3 = 40_000  // ≈상위 10%

    @Published var rateLevel1Min: Int {
        didSet { defaults.set(rateLevel1Min, forKey: "rate_level1_min") }
    }
    @Published var rateLevel2Min: Int {
        didSet { defaults.set(rateLevel2Min, forKey: "rate_level2_min") }
    }
    @Published var rateLevel3Min: Int {
        didSet { defaults.set(rateLevel3Min, forKey: "rate_level3_min") }
    }

    /// 처리율 임계값을 기본값으로 되돌린다.
    func resetRateThresholds() {
        rateLevel1Min = Self.defaultRateLevel1
        rateLevel2Min = Self.defaultRateLevel2
        rateLevel3Min = Self.defaultRateLevel3
    }

    // MARK: - 회고 자동 생성
    /// 회고 발송 주기. 기본 끔.
    @Published var retroInterval: RetroInterval {
        didSet { defaults.set(retroInterval.rawValue, forKey: "retro_interval") }
    }
    /// 새 회고 생성 시 알림 발송 여부. 기본 true.
    @Published var retroNotify: Bool {
        didSet { defaults.set(retroNotify, forKey: "retro_notify") }
    }

    // MARK: - 라이브 어드바이저
    /// 조건 트리거 기반 라이브 조언 사용 여부. 기본 끔(opt-in).
    @Published var advisorEnabled: Bool {
        didSet { defaults.set(advisorEnabled, forKey: "advisor_enabled") }
    }
    /// 휴리스틱 체크 주기(분). 기본 10.
    @Published var advisorIntervalMinutes: Int {
        didSet { defaults.set(advisorIntervalMinutes, forKey: "advisor_interval_minutes") }
    }
    /// 새 조언 생성 시 배지 표시 여부. 기본 true.
    @Published var advisorNotify: Bool {
        didSet { defaults.set(advisorNotify, forKey: "advisor_notify") }
    }
    // MARK: - AI 뉴스 데일리
    /// 뉴스 다이제스트 생성 주기. 기본 끔.
    @Published var newsInterval: NewsInterval {
        didSet { defaults.set(newsInterval.rawValue, forKey: "news_interval") }
    }
    /// 새 뉴스 다이제스트 생성 시 알림 발송 여부. 기본 true.
    @Published var newsNotify: Bool {
        didSet { defaults.set(newsNotify, forKey: "news_notify") }
    }

    private init() {
        accountEmail        = defaults.string(forKey: "account_email") ?? ""
        windowLimitTokens   = defaults.integer(forKey: "limit_window_tokens")
        weeklyLimitTokens   = defaults.integer(forKey: "limit_weekly_tokens")
        codexHomePath       = defaults.string(forKey: "codex_home_path") ?? ""
        claudeEnabled       = defaults.object(forKey: "claude_enabled") as? Bool ?? true
        codexEnabled        = defaults.object(forKey: "codex_enabled") as? Bool ?? true
        rateLevel1Min       = defaults.object(forKey: "rate_level1_min") as? Int ?? Self.defaultRateLevel1
        rateLevel2Min       = defaults.object(forKey: "rate_level2_min") as? Int ?? Self.defaultRateLevel2
        rateLevel3Min       = defaults.object(forKey: "rate_level3_min") as? Int ?? Self.defaultRateLevel3
        retroInterval       = RetroInterval(rawValue: defaults.string(forKey: "retro_interval") ?? "") ?? .off
        retroNotify         = defaults.object(forKey: "retro_notify") as? Bool ?? true
        advisorEnabled      = defaults.object(forKey: "advisor_enabled") as? Bool ?? false
        advisorIntervalMinutes = defaults.object(forKey: "advisor_interval_minutes") as? Int ?? 10
        advisorNotify       = defaults.object(forKey: "advisor_notify") as? Bool ?? true
        newsInterval        = NewsInterval(rawValue: defaults.string(forKey: "news_interval") ?? "") ?? .off
        newsNotify          = defaults.object(forKey: "news_notify") as? Bool ?? true
    }

    func percentRemaining(used: Int, limit: Int) -> Double? {
        guard limit > 0 else { return nil }
        return max(0, 1.0 - Double(used) / Double(limit))
    }
}
