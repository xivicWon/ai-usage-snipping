// ClaudeMonitor/App/AppState.swift
import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var todayCostUSD: Double = 0
    @Published var todayTokens: Int = 0
    @Published var weekCostUSD: Double = 0
    @Published var dailySummaries: [DailySummary] = []

    private let store: SQLiteStore
    private let parser: JSONLParser
    private var watcher: FSEventWatcher?

    private static let claudeProjectsURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/projects")

    init() {
        self.store = (try? SQLiteStore()) ?? { fatalError("SQLiteStore init failed") }()
        self.parser = JSONLParser()
        Task { await self.boot() }
    }

    private func boot() async {
        await scanAll()
        await refresh()
        startWatching()
    }

    // 앱 첫 실행 시 기존 .jsonl 전체 스캔
    private func scanAll() async {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: Self.claudeProjectsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if let records = try? parser.parseNew(in: url), !records.isEmpty {
                try? store.insert(records)
            }
        }
    }

    private func startWatching() {
        watcher = FSEventWatcher(path: Self.claudeProjectsURL) { [weak self] url in
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
        dailySummaries = (try? store.dailySummaries(days: 30)) ?? []
    }
}
