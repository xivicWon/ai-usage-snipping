# ClaudeMonitor Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS 메뉴바 앱 — `~/.claude/projects/**/*.jsonl` 을 실시간 파싱해 오늘 Claude Code 비용을 메뉴바에 표시

**Architecture:** FSEventWatcher 가 파일 변경을 감지하면 JSONLParser 가 새 줄만 증분 파싱하고, PricingTable 로 비용 계산 후 SQLiteStore 에 INSERT. AppState(ObservableObject) 가 집계 쿼리를 MenuBarExtra UI 에 바인딩.

**Tech Stack:** Swift 5.9, SwiftUI, MenuBarExtra (macOS 13+), GRDB.swift (SQLite ORM), FSEvents (Apple framework), XCTest

## Global Constraints

- Deployment target: macOS 13.0 (Ventura) — MenuBarExtra API 최소 버전
- GRDB.swift via Swift Package Manager, from: "6.0.0"
- 앱 샌드박스 비활성화 (`com.apple.security.app-sandbox = false`) — `~/.claude` 직접 접근
- xcodegen 으로 `.xcodeproj` 생성 — 프로젝트 파일 수동 편집 금지
- 모든 파일 경로: 프로젝트 루트 기준 `/Users/wonjaeho/Workspace/claude-monitor/`

---

## 파일 맵

| 경로 | 역할 |
|------|------|
| `project.yml` | xcodegen 프로젝트 정의 |
| `ClaudeMonitor/App/ClaudeMonitorApp.swift` | `@main`, MenuBarExtra + Window Scene |
| `ClaudeMonitor/App/AppState.swift` | ObservableObject, 초기 스캔, FSWatcher 시작 |
| `ClaudeMonitor/Data/PricingTable.swift` | 모델별 단가 enum + cost() |
| `ClaudeMonitor/Data/JSONLParser.swift` | 증분 JSONL 파싱, ParsedRecord 생성 |
| `ClaudeMonitor/Data/SQLiteStore.swift` | GRDB 래퍼, 마이그레이션, 집계 쿼리 |
| `ClaudeMonitor/Data/FSEventWatcher.swift` | FSEvents 래퍼, .jsonl 변경 감지 |
| `ClaudeMonitor/MenuBar/MenuBarView.swift` | 메뉴바 팝업 UI |
| `ClaudeMonitorTests/PricingTableTests.swift` | 단가 계산 유닛 테스트 |
| `ClaudeMonitorTests/JSONLParserTests.swift` | 파싱·증분·엣지케이스 테스트 |
| `ClaudeMonitorTests/SQLiteStoreTests.swift` | INSERT·중복제거·집계 쿼리 테스트 |

---

## Task 1: Xcode 프로젝트 부트스트랩

**Files:**
- Create: `project.yml`
- Create: `ClaudeMonitor/Info.plist`
- Create: `ClaudeMonitor/ClaudeMonitor.entitlements`
- Generated: `ClaudeMonitor.xcodeproj/` (xcodegen 출력)

**Interfaces:**
- Produces: 빌드 가능한 Xcode 프로젝트, GRDB SPM 패키지 해결됨

- [ ] **Step 1: xcodegen 설치**

```bash
brew install xcodegen
xcodegen --version  # 기대 출력: XcodeGen Version: 2.x.x
```

- [ ] **Step 2: project.yml 작성**

```yaml
# /Users/wonjaeho/Workspace/claude-monitor/project.yml
name: ClaudeMonitor
options:
  bundleIdPrefix: com.wonjaeho
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"

packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift
    from: "6.0.0"

targets:
  ClaudeMonitor:
    type: application
    platform: macOS
    sources:
      - ClaudeMonitor
    dependencies:
      - package: GRDB
        product: GRDB
    info:
      path: ClaudeMonitor/Info.plist
      properties:
        CFBundleName: ClaudeMonitor
        CFBundleShortVersionString: "1.0"
        CFBundleVersion: "1"
        LSUIElement: true
        NSHumanReadableDescription: Claude Code usage monitor
    entitlements:
      path: ClaudeMonitor/ClaudeMonitor.entitlements
      properties:
        com.apple.security.app-sandbox: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.wonjaeho.ClaudeMonitor
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        SWIFT_VERSION: "5.9"
        CODE_SIGN_IDENTITY: ""
        CODE_SIGNING_REQUIRED: "NO"

  ClaudeMonitorTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - ClaudeMonitorTests
    dependencies:
      - target: ClaudeMonitor
      - package: GRDB
        product: GRDB
    settings:
      base:
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        SWIFT_VERSION: "5.9"
```

- [ ] **Step 3: 임시 앱 진입점 생성 (xcodegen 소스 필요)**

```swift
// ClaudeMonitor/App/ClaudeMonitorApp.swift  (임시 — Task 7에서 교체)
import SwiftUI
@main struct ClaudeMonitorApp: App {
    var body: some Scene { Settings { EmptyView() } }
}
```

- [ ] **Step 4: 프로젝트 생성**

```bash
cd /Users/wonjaeho/Workspace/claude-monitor
xcodegen generate
# 기대 출력: ✅ Generated: ClaudeMonitor.xcodeproj
```

- [ ] **Step 5: 빌드 확인**

```bash
xcodebuild -project ClaudeMonitor.xcodeproj \
           -scheme ClaudeMonitor \
           -destination 'platform=macOS' \
           build 2>&1 | tail -5
# 기대 출력: ** BUILD SUCCEEDED **
```

- [ ] **Step 6: 커밋**

```bash
git add project.yml ClaudeMonitor/ ClaudeMonitor.xcodeproj/
git commit -m "chore: bootstrap Xcode project with xcodegen and GRDB"
```

---

## Task 2: PricingTable (TDD)

**Files:**
- Create: `ClaudeMonitor/Data/PricingTable.swift`
- Create: `ClaudeMonitorTests/PricingTableTests.swift`

**Interfaces:**
- Produces:
  - `PricingTable.cost(model: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> Double`
  - `ClaudeModel` enum with `rawValue` matching `.jsonl` model strings

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
// ClaudeMonitorTests/PricingTableTests.swift
import XCTest
@testable import ClaudeMonitor

final class PricingTableTests: XCTestCase {

    func test_opus_1M_input_costs_15_dollars() {
        let cost = PricingTable.cost(
            model: "claude-opus-4-8",
            input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0
        )
        XCTAssertEqual(cost, 15.0, accuracy: 0.0001)
    }

    func test_sonnet_1M_output_costs_15_dollars() {
        let cost = PricingTable.cost(
            model: "claude-sonnet-4-6",
            input: 0, output: 1_000_000, cacheRead: 0, cacheWrite: 0
        )
        XCTAssertEqual(cost, 15.0, accuracy: 0.0001)
    }

    func test_haiku_mixed_100k_input_50k_output() {
        // input: 100k * (0.80/1M) = $0.08, output: 50k * (4.0/1M) = $0.20
        let cost = PricingTable.cost(
            model: "claude-haiku-4-5",
            input: 100_000, output: 50_000, cacheRead: 0, cacheWrite: 0
        )
        XCTAssertEqual(cost, 0.28, accuracy: 0.0001)
    }

    func test_sonnet_cache_read_1M_costs_30_cents() {
        let cost = PricingTable.cost(
            model: "claude-sonnet-4-6",
            input: 0, output: 0, cacheRead: 1_000_000, cacheWrite: 0
        )
        XCTAssertEqual(cost, 0.30, accuracy: 0.0001)
    }

    func test_opus_cache_write_1M_costs_18_75() {
        let cost = PricingTable.cost(
            model: "claude-opus-4-8",
            input: 0, output: 0, cacheRead: 0, cacheWrite: 1_000_000
        )
        XCTAssertEqual(cost, 18.75, accuracy: 0.0001)
    }

    func test_unknown_model_returns_nonzero_cost() {
        let cost = PricingTable.cost(
            model: "claude-future-model-99",
            input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0
        )
        XCTAssertGreaterThan(cost, 0)
    }

    func test_all_zero_tokens_returns_zero() {
        let cost = PricingTable.cost(
            model: "claude-sonnet-4-6",
            input: 0, output: 0, cacheRead: 0, cacheWrite: 0
        )
        XCTAssertEqual(cost, 0.0)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
xcodebuild test -project ClaudeMonitor.xcodeproj \
                -scheme ClaudeMonitorTests \
                -destination 'platform=macOS' 2>&1 | grep -E "FAIL|error:|PricingTable"
# 기대: error: cannot find 'PricingTable' in scope
```

- [ ] **Step 3: PricingTable 구현**

```swift
// ClaudeMonitor/Data/PricingTable.swift
import Foundation

enum ClaudeModel: CaseIterable {
    case opus48, sonnet46, haiku45, unknown

    // 모델 문자열 prefix 매칭
    static func from(_ string: String) -> ClaudeModel {
        if string.hasPrefix("claude-opus-4") { return .opus48 }
        if string.hasPrefix("claude-sonnet-4") { return .sonnet46 }
        if string.hasPrefix("claude-haiku-4") { return .haiku45 }
        return .unknown
    }

    var inputPer1M: Double {
        switch self {
        case .opus48:  return 15.0
        case .sonnet46: return 3.0
        case .haiku45: return 0.80
        case .unknown: return 3.0   // sonnet 기본값
        }
    }
    var outputPer1M: Double {
        switch self {
        case .opus48:  return 75.0
        case .sonnet46: return 15.0
        case .haiku45: return 4.0
        case .unknown: return 15.0
        }
    }
    var cacheReadPer1M: Double {
        switch self {
        case .opus48:  return 1.50
        case .sonnet46: return 0.30
        case .haiku45: return 0.08
        case .unknown: return 0.30
        }
    }
    var cacheWritePer1M: Double {
        switch self {
        case .opus48:  return 18.75
        case .sonnet46: return 3.75
        case .haiku45: return 1.00
        case .unknown: return 3.75
        }
    }
}

enum PricingTable {
    static func cost(model modelStr: String, input: Int, output: Int,
                     cacheRead: Int, cacheWrite: Int) -> Double {
        let m = ClaudeModel.from(modelStr)
        return Double(input)      / 1_000_000 * m.inputPer1M
             + Double(output)     / 1_000_000 * m.outputPer1M
             + Double(cacheRead)  / 1_000_000 * m.cacheReadPer1M
             + Double(cacheWrite) / 1_000_000 * m.cacheWritePer1M
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
xcodebuild test -project ClaudeMonitor.xcodeproj \
                -scheme ClaudeMonitorTests \
                -destination 'platform=macOS' 2>&1 | grep -E "Test.*passed|FAIL"
# 기대: Test Suite 'PricingTableTests' passed
```

- [ ] **Step 5: 커밋**

```bash
git add ClaudeMonitor/Data/PricingTable.swift ClaudeMonitorTests/PricingTableTests.swift
git commit -m "feat: add PricingTable with per-model token cost calculation"
```

---

## Task 3: JSONLParser (TDD)

**Files:**
- Create: `ClaudeMonitor/Data/JSONLParser.swift`
- Create: `ClaudeMonitorTests/JSONLParserTests.swift`

**Interfaces:**
- Consumes: `PricingTable.cost(model:input:output:cacheRead:cacheWrite:)` (Task 2)
- Produces:
  - `struct ParsedRecord { id, sessionId, projectPath, model, timestamp, inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens, costUSD }`
  - `final class JSONLParser { func parseNew(in: URL) throws -> [ParsedRecord] }`
  - 증분 파싱: 같은 파일을 두 번 호출하면 새 줄만 반환

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
// ClaudeMonitorTests/JSONLParserTests.swift
import XCTest
@testable import ClaudeMonitor

final class JSONLParserTests: XCTestCase {
    var tempDir: URL!
    var sut: JSONLParser!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = JSONLParser()
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // 실제 .jsonl 형식과 동일한 샘플 라인
    private let sampleLine = """
    {"type":"assistant","uuid":"msg-uuid-001","sessionId":"sess-abc","cwd":"/Users/test/proj","timestamp":"2026-06-26T09:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":200,"cache_creation_input_tokens":100}}}
    """

    func test_parses_assistant_message_fields() throws {
        let file = tempDir.appendingPathComponent("t1.jsonl")
        try sampleLine.write(to: file, atomically: true, encoding: .utf8)

        let records = try sut.parseNew(in: file)

        XCTAssertEqual(records.count, 1)
        let r = records[0]
        XCTAssertEqual(r.id, "msg-uuid-001")
        XCTAssertEqual(r.sessionId, "sess-abc")
        XCTAssertEqual(r.projectPath, "/Users/test/proj")
        XCTAssertEqual(r.model, "claude-sonnet-4-6")
        XCTAssertEqual(r.inputTokens, 1000)
        XCTAssertEqual(r.outputTokens, 500)
        XCTAssertEqual(r.cacheReadTokens, 200)
        XCTAssertEqual(r.cacheWriteTokens, 100)
    }

    func test_cost_is_calculated_from_pricing_table() throws {
        let file = tempDir.appendingPathComponent("t2.jsonl")
        try sampleLine.write(to: file, atomically: true, encoding: .utf8)

        let records = try sut.parseNew(in: file)
        // sonnet: 1000*3/1M + 500*15/1M + 200*0.3/1M + 100*3.75/1M
        let expected = 0.003 + 0.0075 + 0.00006 + 0.000375
        XCTAssertEqual(records[0].costUSD, expected, accuracy: 0.000001)
    }

    func test_skips_non_assistant_types() throws {
        let lines = """
        {"type":"user","timestamp":"2026-06-26T09:00:00.000Z"}
        {"type":"queue-operation","timestamp":"2026-06-26T09:00:00.000Z"}
        \(sampleLine)
        """
        let file = tempDir.appendingPathComponent("t3.jsonl")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        let records = try sut.parseNew(in: file)
        XCTAssertEqual(records.count, 1)
    }

    func test_incremental_parse_returns_only_new_lines() throws {
        let file = tempDir.appendingPathComponent("t4.jsonl")
        try sampleLine.write(to: file, atomically: true, encoding: .utf8)

        let first = try sut.parseNew(in: file)
        XCTAssertEqual(first.count, 1)

        // 두 번째 줄 추가
        let line2 = "\n{\"type\":\"assistant\",\"uuid\":\"msg-uuid-002\",\"sessionId\":\"sess-abc\",\"cwd\":\"/Users/test/proj\",\"timestamp\":\"2026-06-26T09:01:00.000Z\",\"message\":{\"model\":\"claude-opus-4-8\",\"usage\":{\"input_tokens\":2000,\"output_tokens\":800,\"cache_read_input_tokens\":0,\"cache_creation_input_tokens\":0}}}"
        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(line2.data(using: .utf8)!)
        handle.closeFile()

        let second = try sut.parseNew(in: file)
        XCTAssertEqual(second.count, 1)           // 새 줄만
        XCTAssertEqual(second[0].id, "msg-uuid-002")
        XCTAssertEqual(second[0].inputTokens, 2000)
    }

    func test_empty_file_returns_empty_array() throws {
        let file = tempDir.appendingPathComponent("t5.jsonl")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let records = try sut.parseNew(in: file)
        XCTAssertTrue(records.isEmpty)
    }

    func test_assistant_message_without_usage_is_skipped() throws {
        let noUsage = "{\"type\":\"assistant\",\"uuid\":\"u1\",\"sessionId\":\"s\",\"cwd\":\"/p\",\"timestamp\":\"2026-06-26T09:00:00.000Z\",\"message\":{\"model\":\"claude-sonnet-4-6\"}}"
        let file = tempDir.appendingPathComponent("t6.jsonl")
        try noUsage.write(to: file, atomically: true, encoding: .utf8)

        let records = try sut.parseNew(in: file)
        XCTAssertTrue(records.isEmpty)
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
xcodebuild test -project ClaudeMonitor.xcodeproj \
                -scheme ClaudeMonitorTests \
                -destination 'platform=macOS' 2>&1 | grep -E "error:|JSONLParser"
# 기대: error: cannot find 'JSONLParser' in scope
```

- [ ] **Step 3: ParsedRecord 와 JSONLParser 구현**

```swift
// ClaudeMonitor/Data/JSONLParser.swift
import Foundation

struct ParsedRecord {
    let id: String           // JSONL의 message uuid
    let sessionId: String
    let projectPath: String
    let model: String
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int

    var costUSD: Double {
        PricingTable.cost(model: model, input: inputTokens, output: outputTokens,
                          cacheRead: cacheReadTokens, cacheWrite: cacheWriteTokens)
    }
}

final class JSONLParser {
    private var offsets: [String: Int] = [:]  // filePath → last read byte count

    func parseNew(in fileURL: URL) throws -> [ParsedRecord] {
        let data = try Data(contentsOf: fileURL)
        let path = fileURL.path
        let offset = offsets[path, default: 0]
        offsets[path] = data.count

        guard offset < data.count else { return [] }
        let slice = data[offset...]
        guard let text = String(data: slice, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fmt.date(from: s) { return date }
            // Fallback: without fractional seconds
            fmt.formatOptions = [.withInternetDateTime]
            if let date = fmt.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date: \(s)")
        }

        var records: [ParsedRecord] = []
        for line in text.components(separatedBy: "\n") {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  let lineData = line.data(using: .utf8),
                  let raw = try? decoder.decode(RawLine.self, from: lineData),
                  raw.type == "assistant",
                  let msg = raw.message,
                  let usage = msg.usage
            else { continue }

            records.append(ParsedRecord(
                id: raw.uuid ?? "\(raw.sessionId ?? "?")-\(raw.timestamp?.timeIntervalSince1970 ?? 0)",
                sessionId: raw.sessionId ?? "",
                projectPath: raw.cwd ?? "",
                model: msg.model,
                timestamp: raw.timestamp ?? Date(),
                inputTokens: usage.input_tokens,
                outputTokens: usage.output_tokens,
                cacheReadTokens: usage.cache_read_input_tokens ?? 0,
                cacheWriteTokens: usage.cache_creation_input_tokens ?? 0
            ))
        }
        return records
    }
}

// MARK: - Private Decodable types

private struct RawLine: Decodable {
    let type: String
    let uuid: String?
    let sessionId: String?
    let cwd: String?
    let timestamp: Date?
    let message: RawMessage?
}

private struct RawMessage: Decodable {
    let model: String
    let usage: RawUsage?
}

private struct RawUsage: Decodable {
    let input_tokens: Int
    let output_tokens: Int
    let cache_read_input_tokens: Int?
    let cache_creation_input_tokens: Int?
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
xcodebuild test -project ClaudeMonitor.xcodeproj \
                -scheme ClaudeMonitorTests \
                -destination 'platform=macOS' 2>&1 | grep -E "passed|FAIL"
# 기대: Test Suite 'JSONLParserTests' passed
```

- [ ] **Step 5: 커밋**

```bash
git add ClaudeMonitor/Data/JSONLParser.swift ClaudeMonitorTests/JSONLParserTests.swift
git commit -m "feat: add JSONLParser with incremental byte-offset parsing"
```

---

## Task 4: SQLiteStore (TDD)

**Files:**
- Create: `ClaudeMonitor/Data/SQLiteStore.swift`
- Create: `ClaudeMonitorTests/SQLiteStoreTests.swift`

**Interfaces:**
- Consumes: `ParsedRecord` (Task 3)
- Produces:
  - `struct DailySummary: FetchableRecord { date, totalCostUSD, totalInputTokens, totalOutputTokens, sessionCount }`
  - `final class SQLiteStore { init(path:) throws; func insert([ParsedRecord]) throws; func todaySummary() throws -> DailySummary?; func dailySummaries(days:) throws -> [DailySummary] }`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
// ClaudeMonitorTests/SQLiteStoreTests.swift
import XCTest
import GRDB
@testable import ClaudeMonitor

final class SQLiteStoreTests: XCTestCase {
    var sut: SQLiteStore!

    override func setUp() async throws {
        sut = try SQLiteStore(path: ":memory:")
    }

    private func makeRecord(id: String = UUID().uuidString,
                            inputTokens: Int = 1000,
                            outputTokens: Int = 500) -> ParsedRecord {
        ParsedRecord(
            id: id,
            sessionId: "sess-1",
            projectPath: "/Users/test/project",
            model: "claude-sonnet-4-6",
            timestamp: Date(),
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: 0,
            cacheWriteTokens: 0
        )
    }

    func test_insert_and_today_summary() throws {
        try sut.insert([makeRecord()])

        let summary = try sut.todaySummary()
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary!.totalInputTokens, 1000)
        XCTAssertEqual(summary!.totalOutputTokens, 500)
        XCTAssertGreaterThan(summary!.totalCostUSD, 0)
        XCTAssertEqual(summary!.sessionCount, 1)
    }

    func test_insert_ignores_duplicate_ids() throws {
        let record = makeRecord(id: "dup-id", inputTokens: 1000)
        try sut.insert([record])
        try sut.insert([record])  // 동일 id 재삽입

        let summary = try sut.todaySummary()
        XCTAssertEqual(summary!.totalInputTokens, 1000)  // 2000이 아님
    }

    func test_insert_multiple_records_accumulates_tokens() throws {
        try sut.insert([
            makeRecord(id: "r1", inputTokens: 1000),
            makeRecord(id: "r2", inputTokens: 2000),
        ])

        let summary = try sut.todaySummary()
        XCTAssertEqual(summary!.totalInputTokens, 3000)
    }

    func test_daily_summaries_returns_entries_for_last_30_days() throws {
        try sut.insert([makeRecord()])

        let summaries = try sut.dailySummaries(days: 30)
        XCTAssertFalse(summaries.isEmpty)
        XCTAssertGreaterThan(summaries[0].totalCostUSD, 0)
    }

    func test_today_summary_with_no_records_returns_zero_cost() throws {
        let summary = try sut.todaySummary()
        XCTAssertEqual(summary?.totalCostUSD ?? 0, 0.0)
    }
}
```

- [ ] **Step 2: 실패 확인**

```bash
xcodebuild test -project ClaudeMonitor.xcodeproj \
                -scheme ClaudeMonitorTests \
                -destination 'platform=macOS' 2>&1 | grep -E "error:|SQLiteStore"
# 기대: error: cannot find 'SQLiteStore' in scope
```

- [ ] **Step 3: SQLiteStore 구현**

```swift
// ClaudeMonitor/Data/SQLiteStore.swift
import Foundation
import GRDB

struct DailySummary: FetchableRecord {
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

    init(path: String = SQLiteStore.defaultPath) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrate()
    }

    private static var defaultPath: String {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.sqlite").path
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
                WHERE date >= date('now', 'localtime', '-\(days) days')
                GROUP BY date
                ORDER BY date DESC
                """)
        }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
xcodebuild test -project ClaudeMonitor.xcodeproj \
                -scheme ClaudeMonitorTests \
                -destination 'platform=macOS' 2>&1 | grep -E "passed|FAIL"
# 기대: Test Suite 'SQLiteStoreTests' passed
```

- [ ] **Step 5: 커밋**

```bash
git add ClaudeMonitor/Data/SQLiteStore.swift ClaudeMonitorTests/SQLiteStoreTests.swift
git commit -m "feat: add SQLiteStore with GRDB migrations and daily aggregate queries"
```

---

## Task 5: FSEventWatcher + 초기 스캔

**Files:**
- Create: `ClaudeMonitor/Data/FSEventWatcher.swift`

**Interfaces:**
- Consumes: `JSONLParser.parseNew(in:)` (Task 3), `SQLiteStore.insert(_:)` (Task 4)
- Produces:
  - `final class FSEventWatcher { init(path: URL, handler: @escaping (URL) -> Void) }`
  - 파일 변경 시 `.jsonl` 확장자 파일만 handler 호출

- [ ] **Step 1: FSEventWatcher 구현** (FSEvents 는 unit test 가 어려우므로 구현 먼저)

```swift
// ClaudeMonitor/Data/FSEventWatcher.swift
import Foundation

final class FSEventWatcher {
    private var stream: FSEventStreamRef?

    // handler: 변경된 .jsonl 파일의 URL
    init(path: URL, handler: @escaping (URL) -> Void) {
        let paths = [path.path as CFString] as CFArray
        let selfPtr = Unmanaged.passRetained(Box(handler))

        var ctx = FSEventStreamContext(
            version: 0,
            info: selfPtr.toOpaque(),
            retain: nil,
            release: { Unmanaged<Box<(URL) -> Void>>.fromOpaque($0!).release() },
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            let box = Unmanaged<Box<(URL) -> Void>>.fromOpaque(info!).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self)
            for i in 0..<numEvents {
                guard let p = paths[i] as? String else { continue }
                let url = URL(fileURLWithPath: p)
                if url.pathExtension == "jsonl" {
                    box.value(url)
                }
            }
        }

        stream = FSEventStreamCreate(
            nil, callback, &ctx,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,  // 0.5초 debounce
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes
            )
        )
        if let s = stream {
            FSEventStreamScheduleWithRunLoop(s, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(s)
        }
    }

    deinit {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
    }
}

// Swift 클로저를 UnsafeMutableRawPointer 로 전달하기 위한 래퍼
private final class Box<T> {
    let value: T
    init(_ value: T) { self.value = value }
}
```

- [ ] **Step 2: 수동 동작 확인** (빌드만 검증)

```bash
xcodebuild -project ClaudeMonitor.xcodeproj \
           -scheme ClaudeMonitor \
           -destination 'platform=macOS' \
           build 2>&1 | tail -3
# 기대: ** BUILD SUCCEEDED **
```

- [ ] **Step 3: 커밋**

```bash
git add ClaudeMonitor/Data/FSEventWatcher.swift
git commit -m "feat: add FSEventWatcher wrapping FSEvents for .jsonl file changes"
```

---

## Task 6: AppState

**Files:**
- Create: `ClaudeMonitor/App/AppState.swift`

**Interfaces:**
- Consumes: `FSEventWatcher`, `JSONLParser`, `SQLiteStore`, `DailySummary` (Tasks 2-5)
- Produces:
  - `@MainActor final class AppState: ObservableObject`
  - `@Published var todayCostUSD: Double`
  - `@Published var todayTokens: Int`
  - `@Published var weekCostUSD: Double`
  - `@Published var dailySummaries: [DailySummary]`

- [ ] **Step 1: AppState 구현**

```swift
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
```

- [ ] **Step 2: 빌드 확인**

```bash
xcodebuild -project ClaudeMonitor.xcodeproj \
           -scheme ClaudeMonitor \
           -destination 'platform=macOS' \
           build 2>&1 | tail -3
# 기대: ** BUILD SUCCEEDED **
```

- [ ] **Step 3: 커밋**

```bash
git add ClaudeMonitor/App/AppState.swift
git commit -m "feat: add AppState with initial scan and FSEvent-driven refresh"
```

---

## Task 7: MenuBar UI (Phase 1 완성)

**Files:**
- Modify: `ClaudeMonitor/App/ClaudeMonitorApp.swift` (Task 1 임시 파일 교체)
- Create: `ClaudeMonitor/MenuBar/MenuBarView.swift`

**Interfaces:**
- Consumes: `AppState` (Task 6)

- [ ] **Step 1: MenuBarView 작성**

```swift
// ClaudeMonitor/MenuBar/MenuBarView.swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 요약 헤더
            HStack(spacing: 16) {
                statBlock(label: "오늘", value: appState.todayCostUSD.formatted(.currency(code: "USD")))
                Divider().frame(height: 32)
                statBlock(label: "이번 주", value: appState.weekCostUSD.formatted(.currency(code: "USD")))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Text("\(appState.todayTokens.formatted()) tokens")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Divider()

            Button {
                openWindow(id: "dashboard")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("대시보드 열기", systemImage: "chart.bar")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("종료")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 220)
    }

    private func statBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.title3.monospacedDigit().bold())
        }
    }
}
```

- [ ] **Step 2: App 진입점 교체**

```swift
// ClaudeMonitor/App/ClaudeMonitorApp.swift
import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            // 메뉴바 타이틀: 비용이 0이면 $0.00, 아니면 포맷된 금액
            Text(appState.todayCostUSD == 0
                 ? "$0.00"
                 : appState.todayCostUSD.formatted(.currency(code: "USD")))
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)

        Window("대시보드", id: "dashboard") {
            Text("Dashboard — Phase 2에서 구현")  // 플레이스홀더
                .frame(width: 700, height: 500)
                .environmentObject(appState)
        }
        .windowResizability(.contentMinSize)
    }
}
```

- [ ] **Step 3: 빌드 및 실행**

```bash
xcodebuild -project ClaudeMonitor.xcodeproj \
           -scheme ClaudeMonitor \
           -destination 'platform=macOS' \
           build 2>&1 | tail -3
# 기대: ** BUILD SUCCEEDED **
```

```bash
# 앱 실행 후 메뉴바에 "$X.XX" 표시 확인
open /Users/wonjaeho/Workspace/claude-monitor/DerivedData/ClaudeMonitor/Build/Products/Debug/ClaudeMonitor.app
# 또는 Xcode에서 Run (⌘R)
```

- [ ] **Step 4: 동작 검증 체크리스트**
  - [ ] 메뉴바 상단에 "$X.XX" 형태의 비용 표시 확인
  - [ ] 클릭 시 팝업에 오늘/이번 주 비용, 토큰 수 표시
  - [ ] "대시보드 열기" 클릭 시 빈 창 열림
  - [ ] "종료" 클릭 시 앱 종료
  - [ ] Console.app 에서 crash 없음 확인

- [ ] **Step 5: 최종 커밋**

```bash
git add ClaudeMonitor/App/ClaudeMonitorApp.swift ClaudeMonitor/MenuBar/MenuBarView.swift
git commit -m "feat: add MenuBarExtra UI showing today cost — Phase 1 complete"
```

---

## 완료 기준 (Phase 1)

- [ ] 모든 XCTest 통과 (PricingTable, JSONLParser, SQLiteStore)
- [ ] 메뉴바에 오늘 비용 표시
- [ ] `~/.claude/projects` 의 기존 `.jsonl` 초기 스캔 동작
- [ ] 새 Claude Code 세션 시작 시 실시간으로 비용 업데이트

## Phase 2 예고 (별도 계획서)

- `OverviewView` — Swift Charts로 30일 비용 바 차트
- `ProjectBreakdownView` — `cwd` 기반 프로젝트별 비용
- `TokenDetailView` — input/output/cache 비율 차트
