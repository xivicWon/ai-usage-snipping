// ClaudeMonitor/App/AppState.swift
import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var todayCostUSD: Double = 0
    @Published var todayTokens: Int = 0
    @Published var weekCostUSD: Double = 0
    @Published var weekTokens: Int = 0
    @Published var windowTokens: Int = 0   // last 5 hours
    @Published var dailySummaries: [DailySummary] = []
    @Published var weeklyProjects: [ProjectSummary] = []
    @Published var weeklyStats: WeeklyStats = WeeklyStats(cacheHitRate: 0, opusRatio: 0, avgTokensPerCall: 0)

    let limits = UsageLimits.shared
    let profiles = ProfileStore.shared
    let anthropicUsage = AnthropicUsageReader.shared

    private var store: SQLiteStore
    private var parser: JSONLParser
    private var watcher: FSEventWatcher?
    private var profileCancellable: AnyCancellable?

    init() {
        let profile = ProfileStore.shared.activeProfile
        self.store = (try? SQLiteStore(profileId: profile?.id)) ?? { fatalError("SQLiteStore init failed") }()
        self.parser = JSONLParser()
        observeProfileChanges()
        Task { await self.boot(profile: profile) }
    }

    private func observeProfileChanges() {
        profileCancellable = ProfileStore.shared.$activeProfileId
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.switchProfile()
                }
            }
    }

    private func switchProfile() async {
        watcher = nil
        parser = JSONLParser()
        let profile = ProfileStore.shared.activeProfile
        store = (try? SQLiteStore(profileId: profile?.id)) ?? store
        // Reset UI
        todayCostUSD = 0; todayTokens = 0
        weekCostUSD = 0; weekTokens = 0; windowTokens = 0
        dailySummaries = []
        await boot(profile: profile)
    }

    private func boot(profile: Profile?) async {
        updateActiveSymlink(for: profile)
        await scanAll(projectsURL: profile?.projectsURL ?? Self.defaultProjectsURL)
        await refresh()
        startWatching(projectsURL: profile?.projectsURL ?? Self.defaultProjectsURL)
    }

    /// Keeps ~/Library/Application Support/ClaudeMonitor/active.sqlite pointing at
    /// the current profile's DB so external tools can query a stable path.
    private func updateActiveSymlink(for profile: Profile?) {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeMonitor")
        let link = dir.appendingPathComponent("active.sqlite").path
        let target = SQLiteStore.dbPath(for: profile?.id)
        try? FileManager.default.removeItem(atPath: link)
        try? FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
    }

    private static var defaultProjectsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    }

    private func scanAll(projectsURL: URL) async {
        // Run file I/O on a background queue so the main actor / UI stays responsive
        let store = self.store
        let parser = self.parser
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let fm = FileManager.default
                guard let enumerator = fm.enumerator(
                    at: projectsURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continuation.resume(); return }

                for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                    if let records = try? parser.parseNew(in: url), !records.isEmpty {
                        try? store.insert(records)
                    }
                }
                continuation.resume()
            }
        }
    }

    private func startWatching(projectsURL: URL) {
        watcher = FSEventWatcher(path: projectsURL) { [weak self] url in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let records = try? self.parser.parseNew(in: url), !records.isEmpty {
                    try? self.store.insert(records)
                    await self.refresh()
                }
            }
        }
    }

    func refresh() async {
        if let today = try? store.todaySummary() {
            todayCostUSD = today.totalCostUSD
            todayTokens = today.totalInputTokens + today.totalOutputTokens
        }
        let week = (try? store.dailySummaries(days: 7)) ?? []
        weekCostUSD = week.reduce(0) { $0 + $1.totalCostUSD }
        weekTokens = week.reduce(0) { $0 + $1.totalInputTokens + $1.totalOutputTokens }
        windowTokens = (try? store.tokenUsage(lastHours: 5)) ?? 0
        dailySummaries = (try? store.dailySummaries(days: 30)) ?? []
        weeklyProjects = (try? store.weeklyProjectSummaries()) ?? []
        weeklyStats    = (try? store.weeklyStats()) ?? weeklyStats
    }

    // Anthropic API data takes priority; falls back to user-configured limits
    var windowPercentRemaining: Double? {
        if let u = anthropicUsage.usage { return u.fiveHourRemaining }
        return limits.percentRemaining(used: windowTokens, limit: limits.windowLimitTokens)
    }

    var weeklyPercentRemaining: Double? {
        if let u = anthropicUsage.usage { return u.weeklyRemaining }
        return limits.percentRemaining(used: weekTokens, limit: limits.weeklyLimitTokens)
    }
}
