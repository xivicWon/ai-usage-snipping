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

    private init() {
        accountEmail        = defaults.string(forKey: "account_email") ?? ""
        windowLimitTokens   = defaults.integer(forKey: "limit_window_tokens")
        weeklyLimitTokens   = defaults.integer(forKey: "limit_weekly_tokens")
        codexHomePath       = defaults.string(forKey: "codex_home_path") ?? ""
    }

    func percentRemaining(used: Int, limit: Int) -> Double? {
        guard limit > 0 else { return nil }
        return max(0, 1.0 - Double(used) / Double(limit))
    }
}
