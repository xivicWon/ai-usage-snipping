// ClaudeMonitor/Data/SessionFeatureStore.swift
import Foundation
import GRDB

/// 세션 파생 신호(`SessionFeatures`)를 영속화하는 단일 저장소.
/// 원문은 저장하지 않는다 — 회고 집계의 입력이 되는 작은 신호만.
final class SessionFeatureStore {
    let dbQueue: DatabaseQueue   // internal for test access

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrate()
    }

    static func defaultPath() -> String {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("features.sqlite").path
    }

    private func migrate() throws {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "sessionFeature", ifNotExists: true) { t in
                t.column("sessionId", .text).primaryKey()
                t.column("source", .text).notNull()
                t.column("projectPath", .text).notNull()
                t.column("goalCount", .integer).notNull()
                t.column("toolCountsJSON", .text).notNull()
                t.column("filesEditedJSON", .text).notNull()
                t.column("testTouched", .boolean).notNull()
                t.column("errorCount", .integer).notNull()
                t.column("interruptCount", .integer).notNull()
                t.column("totalTokens", .integer).notNull()
                t.column("startedAt", .datetime)
                t.column("endedAt", .datetime)
            }
            try db.create(index: "sessionFeature_on_startedAt",
                          on: "sessionFeature", columns: ["startedAt"], ifNotExists: true)
        }
        m.registerMigration("v2_isBot") { db in
            try db.alter(table: "sessionFeature") { t in
                t.add(column: "isBot", .boolean).notNull().defaults(to: false)
            }
        }
        try m.migrate(dbQueue)
    }

    // MARK: - persistence

    func upsert(_ features: [SessionFeatures]) throws {
        try dbQueue.write { db in
            for f in features {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO sessionFeature
                      (sessionId, source, projectPath, goalCount, toolCountsJSON, filesEditedJSON,
                       testTouched, errorCount, interruptCount, totalTokens, startedAt, endedAt, isBot)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                    """, arguments: [
                        f.sessionId, f.source, f.projectPath, f.goalCount,
                        Self.encode(f.toolCounts), Self.encode(f.filesEdited),
                        f.testTouched, f.errorCount, f.interruptCount, f.totalTokens,
                        f.startedAt, f.endedAt, f.isBot,
                    ])
            }
        }
    }

    func upsert(_ f: SessionFeatures) throws { try upsert([f]) }

    /// startedAt 이 [from, to) 범위에 든 세션들. startedAt 오름차순.
    func features(from: Date, to: Date) throws -> [SessionFeatures] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM sessionFeature
                WHERE startedAt >= ? AND startedAt < ?
                ORDER BY startedAt
                """, arguments: [from, to])
                .map(Self.decode)
        }
    }

    func count() throws -> Int {
        try dbQueue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessionFeature") ?? 0 }
    }

    /// 가장 최근에 갱신된 세션 ≈ 현재 활성 세션. (endedAt, 없으면 startedAt 기준 내림차순)
    /// 라이브 어드바이저의 현재 세션 신호 소스.
    func latestSession() throws -> SessionFeatures? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT * FROM sessionFeature
                ORDER BY COALESCE(endedAt, startedAt) DESC LIMIT 1
                """).map(Self.decode)
        }
    }

    /// 수집된 세션 신호를 전부 삭제한다.
    func deleteAll() throws {
        try dbQueue.write { db in try db.execute(sql: "DELETE FROM sessionFeature") }
    }

    // MARK: - JSON helpers

    private static func encode<T: Encodable>(_ v: T) -> String {
        (try? String(data: JSONEncoder().encode(v), encoding: .utf8) ?? "") ?? ""
    }
    private static func decodeDict(_ s: String?) -> [String: Int] {
        guard let d = s?.data(using: .utf8), let v = try? JSONDecoder().decode([String: Int].self, from: d) else { return [:] }
        return v
    }
    private static func decodeArr(_ s: String?) -> [String] {
        guard let d = s?.data(using: .utf8), let v = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return v
    }
    private static func decode(_ row: Row) -> SessionFeatures {
        SessionFeatures(
            sessionId: row["sessionId"], source: row["source"], projectPath: row["projectPath"],
            goalCount: row["goalCount"],
            toolCounts: decodeDict(row["toolCountsJSON"]),
            filesEdited: decodeArr(row["filesEditedJSON"]),
            testTouched: row["testTouched"], errorCount: row["errorCount"],
            interruptCount: row["interruptCount"], totalTokens: row["totalTokens"],
            startedAt: row["startedAt"], endedAt: row["endedAt"], isBot: row["isBot"]
        )
    }
}
