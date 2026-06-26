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

    private init() {
        accountEmail        = defaults.string(forKey: "account_email") ?? ""
        windowLimitTokens   = defaults.integer(forKey: "limit_window_tokens")
        weeklyLimitTokens   = defaults.integer(forKey: "limit_weekly_tokens")
        codexHomePath       = defaults.string(forKey: "codex_home_path") ?? ""
        claudeEnabled       = defaults.object(forKey: "claude_enabled") as? Bool ?? true
        codexEnabled        = defaults.object(forKey: "codex_enabled") as? Bool ?? true
    }

    func percentRemaining(used: Int, limit: Int) -> Double? {
        guard limit > 0 else { return nil }
        return max(0, 1.0 - Double(used) / Double(limit))
    }
}
