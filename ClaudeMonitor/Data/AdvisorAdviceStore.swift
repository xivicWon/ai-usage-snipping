// ClaudeMonitor/Data/AdvisorAdviceStore.swift
import Foundation
import GRDB

/// 생성된 라이브 조언 1건.
struct AdvisorAdvice: Equatable, Identifiable {
    var id: String
    var condition: String   // AdvisorCondition.rawValue
    var generatedAt: Date
    var body: String
}

/// 생성된 조언을 영속화한다. (별도 파일 advisor.sqlite)
final class AdvisorAdviceStore {
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
        return dir.appendingPathComponent("advisor.sqlite").path
    }

    private func migrate() throws {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "advisorAdvice", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("condition", .text).notNull()
                t.column("generatedAt", .datetime).notNull()
                t.column("body", .text).notNull()
            }
        }
        try m.migrate(dbQueue)
    }

    func save(_ a: AdvisorAdvice) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO advisorAdvice (id, condition, generatedAt, body)
                VALUES (?,?,?,?)
                """, arguments: [a.id, a.condition, a.generatedAt, a.body])
        }
    }

    /// 최신순 전체.
    func all() throws -> [AdvisorAdvice] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM advisorAdvice ORDER BY generatedAt DESC")
                .map(Self.decode)
        }
    }

    func latest() throws -> AdvisorAdvice? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM advisorAdvice ORDER BY generatedAt DESC LIMIT 1")
                .map(Self.decode)
        }
    }

    func count() throws -> Int {
        try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM advisorAdvice") ?? 0 }
    }

    func deleteAll() throws {
        try dbQueue.write { db in try db.execute(sql: "DELETE FROM advisorAdvice") }
    }

    private static func decode(_ row: Row) -> AdvisorAdvice {
        AdvisorAdvice(id: row["id"], condition: row["condition"],
                      generatedAt: row["generatedAt"], body: row["body"])
    }
}
