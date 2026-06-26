// ClaudeMonitor/Data/SQLiteStore.swift
import Foundation
import GRDB

struct HourlyUsage: FetchableRecord {
    var dayOfWeek: Int  // 0=Sun, 1=Mon … 6=Sat
    var hour: Int       // 0–23
    var tokens: Int

    init(row: Row) {
        dayOfWeek = Int(row["dayOfWeek"] as? Int64 ?? 0)
        hour      = Int(row["hour"]      as? Int64 ?? 0)
        tokens    = Int(row["tokens"]    as? Int64 ?? 0)
    }
}

struct ProjectSummary: FetchableRecord, Identifiable {
    var id: String { projectPath }
    var projectPath: String
    var totalTokens: Int
    var recordCount: Int
    var cacheHitRate: Double  // SUM(cacheRead) / SUM(input + cacheRead)

    var projectName: String { URL(fileURLWithPath: projectPath).lastPathComponent }
    var avgTokensPerCall: Int { recordCount > 0 ? totalTokens / recordCount : 0 }

    init(row: Row) {
        projectPath  = row["projectPath"]
        totalTokens  = row["totalTokens"]
        recordCount  = row["recordCount"]
        cacheHitRate = row["cacheHitRate"] as? Double ?? 0
    }
}

struct WeeklyStats {
    var cacheHitRate: Double    // 0–1: cacheRead / (input + cacheRead)
    var opusRatio: Double       // 0–1: opus calls / total calls
    var avgTokensPerCall: Int   // (input+output) per API call
}

struct DailySummary: FetchableRecord, Identifiable {
    var id: String { date }
    var date: String
    var totalCostUSD: Double
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var sessionCount: Int

    init(row: Row) {
        date = row["date"]
        totalCostUSD = row["totalCostUSD"]
        totalInputTokens = row["totalInputTokens"]
        totalOutputTokens = row["totalOutputTokens"]
        sessionCount = row["sessionCount"]
    }
}

final class SQLiteStore {
    let dbQueue: DatabaseQueue  // internal for test access

    init(profileId: UUID? = nil) throws {
        let path = SQLiteStore.dbPath(for: profileId)
        dbQueue = try DatabaseQueue(path: path)
        try migrate()
    }

    static func dbPath(for profileId: UUID?) -> String {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = profileId.map { "data-\($0.uuidString).sqlite" } ?? "data.sqlite"
        return dir.appendingPathComponent(name).path
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "sessionRecord", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("projectPath", .text).notNull()
                t.column("model", .text).notNull()
                t.column("date", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("inputTokens", .integer).notNull()
                t.column("outputTokens", .integer).notNull()
                t.column("cacheReadTokens", .integer).notNull()
                t.column("cacheWriteTokens", .integer).notNull()
                t.column("costUSD", .double).notNull()
            }
            try db.create(index: "sessionRecord_on_date",
                          on: "sessionRecord", columns: ["date"],
                          ifNotExists: true)
        }
        try migrator.migrate(dbQueue)
    }

    func insert(_ records: [ParsedRecord]) throws {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current

        try dbQueue.write { db in
            for r in records {
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO sessionRecord
                      (id, projectPath, model, date, timestamp,
                       inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens, costUSD)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        r.id, r.projectPath, r.model,
                        fmt.string(from: r.timestamp), r.timestamp,
                        r.inputTokens, r.outputTokens,
                        r.cacheReadTokens, r.cacheWriteTokens,
                        r.costUSD
                    ]
                )
            }
        }
    }

    func todaySummary() throws -> DailySummary? {
        try dbQueue.read { db in
            try DailySummary.fetchOne(db, sql: """
                SELECT date('now', 'localtime') AS date,
                       COALESCE(SUM(costUSD), 0.0)      AS totalCostUSD,
                       COALESCE(SUM(inputTokens), 0)    AS totalInputTokens,
                       COALESCE(SUM(outputTokens), 0)   AS totalOutputTokens,
                       COUNT(*)                          AS sessionCount
                FROM sessionRecord
                WHERE date = date('now', 'localtime')
                """)
        }
    }

    func dailySummaries(days: Int = 30) throws -> [DailySummary] {
        try dbQueue.read { db in
            try DailySummary.fetchAll(db, sql: """
                SELECT date,
                       SUM(costUSD)       AS totalCostUSD,
                       SUM(inputTokens)   AS totalInputTokens,
                       SUM(outputTokens)  AS totalOutputTokens,
                       COUNT(*)           AS sessionCount
                FROM sessionRecord
                WHERE date >= date('now', 'localtime', ?)
                GROUP BY date
                ORDER BY date DESC
                """, arguments: ["-\(days) days"])
        }
    }

    /// Per-project token usage for the current Mon–Sun week.
    func weeklyProjectSummaries() throws -> [ProjectSummary] {
        try dbQueue.read { db in
            try ProjectSummary.fetchAll(db, sql: """
                SELECT projectPath,
                       SUM(inputTokens + outputTokens)    AS totalTokens,
                       COUNT(*)                            AS recordCount,
                       CAST(SUM(cacheReadTokens) AS REAL)
                         / MAX(SUM(inputTokens + cacheReadTokens), 1) AS cacheHitRate
                FROM sessionRecord
                WHERE date >= date('now', 'localtime', 'weekday 0', '-6 days')
                  AND date <= date('now', 'localtime')
                GROUP BY projectPath
                ORDER BY totalTokens DESC
                LIMIT 20
                """)
        }
    }

    /// Token usage grouped by day-of-week × hour for the current Mon–Sun week.
    func weeklyHourlyUsage() throws -> [HourlyUsage] {
        try dbQueue.read { db in
            try HourlyUsage.fetchAll(db, sql: """
                SELECT
                  CAST(strftime('%w', timestamp, 'localtime') AS INTEGER) AS dayOfWeek,
                  CAST(strftime('%H', timestamp, 'localtime') AS INTEGER) AS hour,
                  SUM(inputTokens + outputTokens) AS tokens
                FROM sessionRecord
                WHERE date >= date('now', 'localtime', 'weekday 0', '-6 days')
                  AND date <= date('now', 'localtime')
                GROUP BY dayOfWeek, hour
                """)
        }
    }

    /// Efficiency metrics for the current Mon–Sun week.
    func weeklyStats() throws -> WeeklyStats {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT
                  CAST(SUM(cacheReadTokens) AS REAL)
                    / MAX(SUM(inputTokens + cacheReadTokens), 1)  AS cacheHitRate,
                  CAST(SUM(CASE WHEN model LIKE '%opus%' THEN 1 ELSE 0 END) AS REAL)
                    / MAX(COUNT(*), 1)                            AS opusRatio,
                  SUM(inputTokens + outputTokens)
                    / MAX(COUNT(*), 1)                            AS avgTokensPerCall
                FROM sessionRecord
                WHERE date >= date('now', 'localtime', 'weekday 0', '-6 days')
                  AND date <= date('now', 'localtime')
                """)
            guard let row = rows.first else {
                return WeeklyStats(cacheHitRate: 0, opusRatio: 0, avgTokensPerCall: 0)
            }
            return WeeklyStats(
                cacheHitRate:      row["cacheHitRate"]      as? Double ?? 0,
                opusRatio:         row["opusRatio"]         as? Double ?? 0,
                avgTokensPerCall:  Int(row["avgTokensPerCall"] as? Int64 ?? 0)
            )
        }
    }

    /// Total tokens used in the last N hours (rolling window).
    func tokenUsage(lastHours hours: Int) throws -> Int {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT COALESCE(SUM(inputTokens + outputTokens), 0) AS total
                FROM sessionRecord
                WHERE timestamp >= datetime('now', ?)
                """, arguments: ["-\(hours) hours"])
            return rows.first.map { Int($0["total"] as Int64) } ?? 0
        }
    }
}
