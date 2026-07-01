// ClaudeMonitor/Data/RetrospectiveReportStore.swift
import Foundation
import GRDB

/// 생성된 회고를 영속화한다. (별도 파일 retrospectives.sqlite — features 와 분리)
final class RetrospectiveReportStore {
    let dbQueue: DatabaseQueue

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrate()
    }

    static func defaultPath() -> String {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("retrospectives.sqlite").path
    }

    private func migrate() throws {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "retrospectiveReport", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("periodLabel", .text).notNull()
                t.column("from", .datetime).notNull()
                t.column("to", .datetime).notNull()
                t.column("generatedAt", .datetime).notNull()
                t.column("body", .text).notNull()
                t.column("humanSessions", .integer).notNull()
                t.column("botSessions", .integer).notNull()
            }
        }
        m.registerMigration("v2_style") { db in
            try db.alter(table: "retrospectiveReport") { t in
                t.add(column: "style", .text).notNull().defaults(to: RetroStyle.standard.rawValue)
            }
        }
        try m.migrate(dbQueue)
    }

    // MARK: - persistence

    func save(_ r: RetrospectiveReport) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO retrospectiveReport
                  (id, periodLabel, "from", "to", generatedAt, body, humanSessions, botSessions, style)
                VALUES (?,?,?,?,?,?,?,?,?)
                """, arguments: [r.id, r.periodLabel, r.from, r.to, r.generatedAt, r.body,
                                 r.humanSessions, r.botSessions, r.style.rawValue])
        }
    }

    /// 최신순(생성시각 내림차순) 전체.
    func all() throws -> [RetrospectiveReport] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM retrospectiveReport ORDER BY generatedAt DESC")
                .map(Self.decode)
        }
    }

    /// 가장 최근 회고.
    func latest() throws -> RetrospectiveReport? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM retrospectiveReport ORDER BY generatedAt DESC LIMIT 1")
                .map(Self.decode)
        }
    }

    func count() throws -> Int {
        try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM retrospectiveReport") ?? 0 }
    }

    /// 저장된 회고를 전부 삭제한다.
    func deleteAll() throws {
        try dbQueue.write { db in try db.execute(sql: "DELETE FROM retrospectiveReport") }
    }

    private static func decode(_ row: Row) -> RetrospectiveReport {
        RetrospectiveReport(
            id: row["id"], periodLabel: row["periodLabel"],
            from: row["from"], to: row["to"], generatedAt: row["generatedAt"],
            body: row["body"], humanSessions: row["humanSessions"], botSessions: row["botSessions"],
            style: RetroStyle(rawValue: row["style"]) ?? .standard
        )
    }
}
