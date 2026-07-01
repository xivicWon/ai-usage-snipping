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
    @Published var weeklyStats: WeeklyStats = WeeklyStats(avgContextSize: 0, opusRatio: 0, avgTokensPerCall: 0)
    @Published var weeklyHourly: [HourlyUsage] = []
    @Published var tokenRateLevel: Int = 0   // 0 미사용, 1 기본, 2 많음, 3 폭발적

    let limits = UsageLimits.shared
    let profiles = ProfileStore.shared
    let anthropicUsage = AnthropicUsageReader.shared

    private var store: SQLiteStore
    private var parser: JSONLParser
    /// 회고 수집 — 세션 파생 신호. 본 usage 파이프라인과 독립(best-effort, 단일 저장소).
    private let featureParser = ClaudeSessionFeatureParser()
    private let featureStore: SessionFeatureStore? = try? SessionFeatureStore(path: SessionFeatureStore.defaultPath())
    private var watcher: FSEventWatcher?

    // 회고 자동 생성 스케줄
    private let retroReportStore: RetrospectiveReportStore? = try? RetrospectiveReportStore(path: RetrospectiveReportStore.defaultPath())
    private var retroEngine: RetrospectiveEngine?
    private var retroTimer: Timer?
    private var isGeneratingRetro = false
    private var profileCancellable: AnyCancellable?
    private var tokenHistory: [(date: Date, tokens: Int)] = []

    init() {
        let profile = ProfileStore.shared.activeProfile
        self.store = (try? SQLiteStore(profileId: profile?.id)) ?? { fatalError("SQLiteStore init failed") }()
        self.parser = JSONLParser()
        observeProfileChanges()
        ClaudeCodeHUDConnector.shared.autoRegisterOnFirstLaunch()
        setupRetroSchedule()
        Task { await self.boot(profile: profile) }
    }

    // MARK: - 회고 자동 생성 스케줄

    private func setupRetroSchedule() {
        if let fs = featureStore, let rs = retroReportStore {
            let runner = ClaudeHeadlessRunner(runner: ProcessCommandRunner())
            retroEngine = RetrospectiveEngine(featureStore: fs, reportStore: rs,
                                              generate: { try runner.run(prompt: $0, timeout: 180) })
        }
        RetroNotifier.shared.requestAuthorization()
        // 부팅 직후 1회 + 30분마다 점검 (앱이 꺼져 놓친 주기를 다음 실행 때 따라잡음)
        retroTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkRetroSchedule() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.checkRetroSchedule() }
    }

    /// 주기가 도래했으면 회고를 생성·저장하고 (설정 시) 알림한다.
    func checkRetroSchedule() {
        guard !isGeneratingRetro,
              let engine = retroEngine, let store = retroReportStore else { return }
        let interval = UsageLimits.shared.retroInterval
        guard let period = interval.period else { return }   // off
        let last = try? store.latest()?.generatedAt
        guard RetrospectiveScheduler.isDue(interval: interval, lastGeneratedAt: last ?? nil, now: Date())
        else { return }

        isGeneratingRetro = true
        let notify = UsageLimits.shared.retroNotify
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let report = try? engine.generate(period: period)
            DispatchQueue.main.async {
                self?.isGeneratingRetro = false
                if let report {
                    RetroBadge.shared.refresh()   // 서명 무관 배지
                    if notify {                    // OS 알림(정식 서명 시 동작)
                        RetroNotifier.shared.notifyNewRetrospective(periodLabel: report.periodLabel)
                    }
                }
            }
        }
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
        let featureParser = self.featureParser
        let featureStore = self.featureStore
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
                    // 회고 수집(backfill 포함) — 파일 전체 → 세션 피처 upsert
                    if let featureStore, let f = try? featureParser.parse(url) {
                        try? featureStore.upsert(f)
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
                // 회고 수집 — 변경된 세션 파일 재파싱 후 upsert
                if let featureStore = self.featureStore, let f = try? self.featureParser.parse(url) {
                    try? featureStore.upsert(f)
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
        weeklyHourly   = (try? store.weeklyHourlyUsage()) ?? []
        recordTokenRate()
    }

    private func recordTokenRate() {
        let now = Date()
        tokenHistory.append((date: now, tokens: windowTokens))
        tokenHistory = tokenHistory.filter { now.timeIntervalSince($0.date) < 180 }

        let oneMinAgo = now.addingTimeInterval(-60)
        let recent = tokenHistory.filter { $0.date >= oneMinAgo }
        guard recent.count >= 2, let earliest = recent.min(by: { $0.date < $1.date }) else { return }

        let delta = max(0, windowTokens - earliest.tokens)
        // 단계 임계값은 설정(UsageLimits)에서 사용자가 조정 가능. 기본값은 실제 처리율 분포 기반.
        let limits = UsageLimits.shared
        switch delta {
        case ..<limits.rateLevel1Min: tokenRateLevel = 0
        case ..<limits.rateLevel2Min: tokenRateLevel = 1
        case ..<limits.rateLevel3Min: tokenRateLevel = 2
        default:                      tokenRateLevel = 3
        }
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
