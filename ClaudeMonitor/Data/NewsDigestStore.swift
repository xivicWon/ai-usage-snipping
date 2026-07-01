// ClaudeMonitor/Data/NewsDigestStore.swift
import Foundation
import GRDB

/// 생성된 뉴스 다이제스트를 영속화한다. (별도 파일 news.sqlite)
final class NewsDigestStore {
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
        return dir.appendingPathComponent("news.sqlite").path
    }

    private func migrate() throws {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "newsDigest", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("generatedAt", .datetime).notNull()
                t.column("body", .text).notNull()
                t.column("itemCount", .integer).notNull()
                t.column("sourceCount", .integer).notNull()
            }
        }
        try m.migrate(dbQueue)
    }

    // MARK: - persistence

    func save(_ d: NewsDigest) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO newsDigest
                  (id, generatedAt, body, itemCount, sourceCount)
                VALUES (?,?,?,?,?)
                """, arguments: [d.id, d.generatedAt, d.body, d.itemCount, d.sourceCount])
        }
    }

    /// 최신순(생성시각 내림차순) 전체.
    func all() throws -> [NewsDigest] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM newsDigest ORDER BY generatedAt DESC")
                .map(Self.decode)
        }
    }

    /// 가장 최근 다이제스트.
    func latest() throws -> NewsDigest? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM newsDigest ORDER BY generatedAt DESC LIMIT 1")
                .map(Self.decode)
        }
    }

    func count() throws -> Int {
        try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM newsDigest") ?? 0 }
    }

    /// 저장된 다이제스트를 전부 삭제한다.
    func deleteAll() throws {
        try dbQueue.write { db in try db.execute(sql: "DELETE FROM newsDigest") }
    }

    private static func decode(_ row: Row) -> NewsDigest {
        NewsDigest(
            id: row["id"], generatedAt: row["generatedAt"],
            body: row["body"], itemCount: row["itemCount"], sourceCount: row["sourceCount"]
        )
    }
}
