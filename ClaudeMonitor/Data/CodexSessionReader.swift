// ClaudeMonitor/Data/CodexSessionReader.swift
import Foundation
import Combine

struct CodexSession: Identifiable {
    var id: String
    var projectName: String
    var cwd: String
    var startedAt: Date
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var primaryUsedPercent: Double
    var primaryResetsAt: Date?

    var totalTokens: Int { totalInputTokens + totalOutputTokens }
}

struct CodexProjectSummary: Identifiable {
    var id: String { projectPath }
    var projectPath: String
    var totalTokens: Int
    var sessionCount: Int
    var projectName: String { URL(fileURLWithPath: projectPath).lastPathComponent }
}

struct CodexDailySummary: Identifiable {
    var id: String { date }
    var date: String
    var totalTokens: Int
    var sessionCount: Int
}

final class CodexSessionReader: ObservableObject {
    static let shared = CodexSessionReader()

    @Published private(set) var sessions: [CodexSession] = []
    @Published private(set) var weeklyProjects: [CodexProjectSummary] = []
    @Published private(set) var dailySummaries: [CodexDailySummary] = []
    @Published private(set) var weeklyTokens: Int = 0
    @Published private(set) var todayTokens: Int = 0
    @Published private(set) var primaryUsedPercent: Double = 0
    @Published private(set) var primaryResetsAt: Date? = nil

    private var timer: Timer?

    private var codexHomePath: String {
        let stored = UserDefaults.standard.string(forKey: "codex_home_path") ?? ""
        return stored.isEmpty
            ? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex").path
            : stored
    }

    private init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.reload()
        }
    }

    func reload() {
        let homePath = codexHomePath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let sessions = Self.loadSessions(from: homePath)
            let stats = Self.computeStats(sessions: sessions)
            DispatchQueue.main.async {
                self?.sessions = sessions
                self?.weeklyProjects = stats.projects
                self?.dailySummaries = stats.dailies
                self?.weeklyTokens = stats.weeklyTokens
                self?.todayTokens = stats.todayTokens
                self?.primaryUsedPercent = stats.primaryUsedPct
                self?.primaryResetsAt = stats.primaryResetsAt
            }
        }
    }

    // MARK: - Parsing

    private static func loadSessions(from homePath: String) -> [CodexSession] {
        let dir = URL(fileURLWithPath: homePath).appendingPathComponent("archived_sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { parseSession(from: $0) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private static func parseSession(from url: URL) -> CodexSession? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        var sessionId: String?
        var cwd: String?
        var startedAt: Date?
        var totalInput = 0
        var totalOutput = 0
        var primaryUsedPct = 0.0
        var primaryResetsAt: Date? = nil

        for line in text.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            let type = json["type"] as? String ?? ""

            switch type {
            case "session_meta":
                if let payload = json["payload"] as? [String: Any] {
                    sessionId = payload["id"] as? String
                    cwd = payload["cwd"] as? String
                    if let tsStr = payload["timestamp"] as? String {
                        startedAt = isoFull.date(from: tsStr) ?? isoBasic.date(from: tsStr)
                    }
                }

            case "event_msg":
                if let payload = json["payload"] as? [String: Any],
                   payload["type"] as? String == "token_count",
                   let info = payload["info"] as? [String: Any],
                   let total = info["total_token_usage"] as? [String: Any] {
                    totalInput  = total["input_tokens"]  as? Int ?? totalInput
                    totalOutput = total["output_tokens"] as? Int ?? totalOutput

                    if let rl = payload["rate_limits"] as? [String: Any],
                       let primary = rl["primary"] as? [String: Any] {
                        primaryUsedPct = primary["used_percent"] as? Double ?? primaryUsedPct
                        if let ts = (primary["resets_at"] as? Double) {
                            primaryResetsAt = Date(timeIntervalSince1970: ts)
                        } else if let ts = (primary["resets_at"] as? Int) {
                            primaryResetsAt = Date(timeIntervalSince1970: Double(ts))
                        }
                    }
                }

            default: break
            }
        }

        guard let id = sessionId, let cwdPath = cwd, let date = startedAt else { return nil }
        return CodexSession(
            id: id,
            projectName: URL(fileURLWithPath: cwdPath).lastPathComponent,
            cwd: cwdPath,
            startedAt: date,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            primaryUsedPercent: primaryUsedPct,
            primaryResetsAt: primaryResetsAt
        )
    }

    // MARK: - Stats

    private struct Stats {
        var projects: [CodexProjectSummary]
        var dailies: [CodexDailySummary]
        var weeklyTokens: Int
        var todayTokens: Int
        var primaryUsedPct: Double
        var primaryResetsAt: Date?
    }

    private static func computeStats(sessions: [CodexSession]) -> Stats {
        let cal = Calendar.current
        let now = Date()
        let sevenDaysAgo = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now
        let todayStart = cal.startOfDay(for: now)

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        var projectMap: [String: (tokens: Int, count: Int)] = [:]
        var dailyMap: [String: (tokens: Int, count: Int)] = [:]
        var weeklyTokens = 0
        var todayTokens = 0
        var latestDate = Date.distantPast
        var latestPct = 0.0
        var latestResets: Date? = nil

        for s in sessions {
            if s.startedAt > latestDate {
                latestDate = s.startedAt
                latestPct = s.primaryUsedPercent
                latestResets = s.primaryResetsAt
            }
            guard s.startedAt >= sevenDaysAgo else { continue }
            let toks = s.totalTokens
            weeklyTokens += toks
            let ex = projectMap[s.cwd] ?? (0, 0)
            projectMap[s.cwd] = (ex.tokens + toks, ex.count + 1)
            let key = dateFmt.string(from: s.startedAt)
            let dx = dailyMap[key] ?? (0, 0)
            dailyMap[key] = (dx.tokens + toks, dx.count + 1)
            if s.startedAt >= todayStart { todayTokens += toks }
        }

        let projects = projectMap.map { path, v in
            CodexProjectSummary(projectPath: path, totalTokens: v.tokens, sessionCount: v.count)
        }.sorted { $0.totalTokens > $1.totalTokens }

        let dailies = dailyMap.map { date, v in
            CodexDailySummary(date: date, totalTokens: v.tokens, sessionCount: v.count)
        }.sorted { $0.date > $1.date }

        return Stats(
            projects: projects,
            dailies: dailies,
            weeklyTokens: weeklyTokens,
            todayTokens: todayTokens,
            primaryUsedPct: latestPct,
            primaryResetsAt: latestResets
        )
    }
}
