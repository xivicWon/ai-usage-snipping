// ClaudeMonitor/Data/AnthropicUsageReader.swift
import Foundation
import Combine

struct AnthropicUsage {
    var fiveHourPercentUsed: Int
    var weeklyPercentUsed: Int
    var fiveHourResetsAt: Date?
    var weeklyResetsAt: Date?
    var fetchedAt: Date

    var fiveHourRemaining: Double { max(0, Double(100 - fiveHourPercentUsed)) / 100 }
    var weeklyRemaining: Double   { max(0, Double(100 - weeklyPercentUsed)) / 100 }

    func minutesUntilReset(_ date: Date?) -> Double? {
        guard let date else { return nil }
        return date.timeIntervalSinceNow / 60
    }

    func shortTimeUntilReset(_ date: Date?) -> String? {
        guard let date else { return nil }
        let diff = date.timeIntervalSinceNow
        guard diff > 0 else { return "곧 갱신" }
        if diff < 3600 { return String(format: "%.0f분 남음", diff / 60) }
        return String(format: "%.0f시간 %.0f분 남음",
                      floor(diff / 3600),
                      (diff.truncatingRemainder(dividingBy: 3600)) / 60)
    }

    func timeUntilReset(_ date: Date?) -> String? {
        guard let date else { return nil }
        let diff = date.timeIntervalSinceNow
        guard diff > 0 else { return "곧 갱신" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        let relative: String
        if diff < 3600 {
            relative = String(format: "%.0f분 후", diff / 60)
        } else {
            relative = String(format: "%.0f시간 후", diff / 3600)
        }
        fmt.dateFormat = Calendar.current.isDateInToday(date) ? "a h:mm" : "M/d"
        return "\(relative) · \(fmt.string(from: date))"
    }
}

/// Reads Claude Code rate limit data from any available HUD cache.
///
/// Tier① 적응형: 우리 캐시(~/.claudemonitor/hud-cache.json)뿐 아니라, 이미 statusLine
/// 을 받고 있는 외부 HUD(OMC 등)의 캐시도 후보로 보고, 그중 **가장 최신·유효한 것**을
/// 읽는다. 이렇게 하면 OMC 가 데이터를 제공할 때는 settings 를 전혀 건드리지 않고도
/// 동작한다. 외부 소스가 없으면 ClaudeMonitor 가 직접 등록한 캐시를 읽는다.
final class AnthropicUsageReader: ObservableObject {
    static let shared = AnthropicUsageReader()

    @Published private(set) var usage: AnthropicUsage?
    @Published private(set) var cacheAge: String = ""
    @Published private(set) var isConnected = false
    /// 현재 표시 중인 데이터의 출처 경로 (홈은 ~ 로 축약)
    @Published private(set) var sourcePath: String?

    /// 알려진 고정 후보 — 빠른 경로. 실제 선택은 mtime(최신성)으로 한다.
    private let knownPaths: [URL] = {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return [
            home.appendingPathComponent(".claudemonitor/hud-cache.json"),        // 우리 캐시
            home.appendingPathComponent(".claude/.omc/state/hud-stdin-cache.json") // OMC 원본 stdin 캐시
        ]
    }()

    /// 탐색(grep식)으로 발견한 추가 후보 — 백그라운드에서 주기적으로 갱신. 스레드 보호.
    private var discoveredPaths: [URL] = []
    private let lock = NSLock()
    private var discoveryTimer: DispatchSourceTimer?
    private var reloadTimer: DispatchSourceTimer?

    private var watchers: [DispatchSourceFileSystemObject] = []

    private init() {
        reload()
        startWatching()
        startReloadTimer()
        startDiscovery()
    }

    /// 알려진 캐시를 짧은 주기로 다시 읽는다.
    /// hud.sh 가 hud-cache.json 을 제자리 덮어쓰기(`>`)하면 디렉터리 감시가 울리지 않아
    /// 5분 discovery 타이머에만 의존하게 되므로, 15초 폴링으로 최신값을 반영한다.
    private func startReloadTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in self?.reload() }
        timer.resume()
        reloadTimer = timer
    }

    private func allCandidates() -> [URL] {
        lock.lock(); let d = discoveredPaths; lock.unlock()
        // 중복 제거(고정 후보 우선)
        var seen = Set<String>(); var result: [URL] = []
        for url in knownPaths + d where seen.insert(url.standardizedFileURL.path).inserted {
            result.append(url)
        }
        return result
    }

    private func bestUsage() -> (usage: AnthropicUsage, mtime: Date, url: URL)? {
        var best: (usage: AnthropicUsage, mtime: Date, url: URL)?
        for path in allCandidates() {
            guard let data = try? Data(contentsOf: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rateLimits = json["rate_limits"] as? [String: Any] else { continue }

            let attrs = try? FileManager.default.attributesOfItem(atPath: path.path)
            let mtime = (attrs?[.modificationDate] as? Date) ?? .distantPast
            let usage = Self.parse(rateLimits: rateLimits, fetchedAt: mtime)
            if best == nil || mtime > best!.mtime { best = (usage, mtime, path) }
        }
        return best
    }

    func reload() {
        guard let best = bestUsage() else {
            DispatchQueue.main.async {
                self.usage = nil
                self.isConnected = false
                self.cacheAge = ""
                self.sourcePath = nil
            }
            return
        }

        DispatchQueue.main.async {
            self.usage = best.usage
            self.isConnected = true
            self.sourcePath = Self.prettyPath(best.url)
            let age = Int(Date().timeIntervalSince(best.mtime) / 60)
            self.cacheAge = age < 2 ? "방금 전" : "\(age)분 전"
        }
    }

    /// [자동 분석 및 연결] 버튼용 — 즉시 탐색을 1회 강제하고, 데이터를 찾았는지와
    /// (찾았다면) 그 출처 경로를 콜백한다.
    func rediscover(_ completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let found = self.discoverCaches()
            self.lock.lock(); self.discoveredPaths = found; self.lock.unlock()
            let best = self.bestUsage()
            let path = best.map { Self.prettyPath($0.url) }
            DispatchQueue.main.async {
                self.reload()
                completion(best != nil, path)
            }
        }
    }

    static func prettyPath(_ url: URL) -> String {
        let home = NSHomeDirectory()
        let p = url.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    /// 우리 캐시(~/.claudemonitor/hud-cache.json)가 아닌 후보 중 최근(기본 30분) rate_limits
    /// 데이터가 있는지 — 커넥터의 Tier①(외부 소스 사용 중) 판단용. 탐색 결과도 포함한다.
    func hasFreshExternalData(within seconds: TimeInterval = 1800) -> Bool {
        let now = Date()
        for path in allCandidates() where !path.path.contains(".claudemonitor/hud-cache.json") {
            guard let data = try? Data(contentsOf: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["rate_limits"] is [String: Any] else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: path.path)
            let mtime = (attrs?[.modificationDate] as? Date) ?? .distantPast
            if now.timeIntervalSince(mtime) < seconds { return true }
        }
        return false
    }

    private static func parse(rateLimits: [String: Any], fetchedAt: Date) -> AnthropicUsage {
        let fiveHour = rateLimits["five_hour"] as? [String: Any]
        let sevenDay = rateLimits["seven_day"] as? [String: Any]
        return AnthropicUsage(
            fiveHourPercentUsed: pct(fiveHour?["used_percentage"]),
            weeklyPercentUsed:   pct(sevenDay?["used_percentage"]),
            fiveHourResetsAt: epoch(fiveHour?["resets_at"]),
            weeklyResetsAt:   epoch(sevenDay?["resets_at"]),
            fetchedAt:        fetchedAt
        )
    }

    /// used_percentage 는 정수(41)일 수도, 부동소수점(28.999…)일 수도 있다.
    /// `as? Int` 는 float 에서 실패하므로 NSNumber 로 읽어 반올림한다.
    private static func pct(_ value: Any?) -> Int {
        guard let n = value as? NSNumber else { return 0 }
        return Int(n.doubleValue.rounded())
    }

    private static func epoch(_ value: Any?) -> Date? {
        guard let n = value as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: n.doubleValue)
    }

    private func startWatching() {
        // 알려진 후보들의 상위 디렉터리를 감시 — 쓰기/생성 모두 포착
        let dirs = Set(knownPaths.map { $0.deletingLastPathComponent().path })
        for dirPath in dirs {
            let fd = open(dirPath, O_EVTONLY)
            guard fd >= 0 else { continue }   // 없는 디렉터리(예: OMC 미설치)는 건너뜀
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write], queue: .global(qos: .utility)
            )
            src.setEventHandler { [weak self] in self?.reload() }
            src.setCancelHandler { close(fd) }
            src.resume()
            watchers.append(src)
        }
    }

    // MARK: - 탐색(grep식) 발견

    /// 백그라운드에서 즉시 1회 + 이후 5분마다 rate_limits 캐시를 탐색한다.
    private func startDiscovery() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 300)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let found = self.discoverCaches()
            self.lock.lock(); self.discoveredPaths = found; self.lock.unlock()
            self.reload()
        }
        timer.resume()
        discoveryTimer = timer
    }

    /// `~/.claude`(+`~/.claudemonitor`)를 가지치기하며 훑어, rate_limits 스키마를 가진
    /// 최근(24h) JSON 파일을 찾는다. 문자열 매칭이 아니라 실제 파싱+스키마 검증으로 오탐 방지.
    private func discoverCaches() -> [URL] {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let roots = [home.appendingPathComponent(".claude"),
                     home.appendingPathComponent(".claudemonitor")]
        // 무거운/무관한 디렉터리는 건너뛴다
        let skipDirs: Set<String> = [
            "projects", "node_modules", "todos", "shell-snapshots",
            "statsig", "logs", "history", ".git", "downloads", "ide"
        ]
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var found: [URL] = []
        var scanned = 0
        let scanCap = 4000   // 폭주 방지 상한

        for root in roots {
            guard let en = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
                options: []
            ) else { continue }

            for case let url as URL in en {
                if scanned >= scanCap { break }
                let vals = try? url.resourceValues(
                    forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
                if vals?.isDirectory == true {
                    if skipDirs.contains(url.lastPathComponent.lowercased()) { en.skipDescendants() }
                    continue
                }
                guard url.pathExtension == "json" else { continue }
                scanned += 1
                let size  = vals?.fileSize ?? 0
                let mtime = vals?.contentModificationDate ?? .distantPast
                guard size > 0, size < 65_536, mtime > cutoff else { continue }
                if isRateLimitCache(url) { found.append(url) }
            }
        }

        // OMC 등은 캐시를 프로젝트별 <cwd>/.omc/state/ 에 쓴다. ~/.claude/projects 의
        // 활성 transcript 에서 cwd 를 역추적해 그 경로들을 추가로 probe 한다.
        found.append(contentsOf: discoverProjectCaches())
        return found
    }

    /// 활성 프로젝트(최근 7일 transcript)의 cwd 를 역추적해 <cwd>/.omc/state/hud-stdin-cache.json 을 찾는다.
    private func discoverProjectCaches() -> [URL] {
        let fm = FileManager.default
        let projectsDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return [] }

        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        var seenCwd = Set<String>()
        var found: [URL] = []

        for dir in projectDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            let jsonls = files.filter { $0.pathExtension == "jsonl" }
            guard let newest = jsonls.max(by: { fileMTime($0) < fileMTime($1) }),
                  fileMTime(newest) > weekAgo,
                  let cwd = firstCwd(in: newest),
                  seenCwd.insert(cwd).inserted else { continue }

            let cache = URL(fileURLWithPath: cwd)
                .appendingPathComponent(".omc/state/hud-stdin-cache.json")
            if isRateLimitCache(cache) { found.append(cache) }
        }
        return found
    }

    /// 파일이 24h 내 수정 + 64KB 미만 + rate_limits 스키마를 갖는 유효 캐시인지.
    private func isRateLimitCache(_ url: URL, maxAge: TimeInterval = 24 * 3600) -> Bool {
        let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let size  = vals?.fileSize ?? 0
        let mtime = vals?.contentModificationDate ?? .distantPast
        guard size > 0, size < 65_536, mtime > Date().addingTimeInterval(-maxAge) else { return false }
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = json["rate_limits"] as? [String: Any],
              let five = rl["five_hour"] as? [String: Any],
              five["used_percentage"] != nil else { return false }
        return true
    }

    private func fileMTime(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    /// transcript JSONL 앞부분에서 첫 `cwd` 값을 읽는다 (전체 로드 없이 8KB만).
    private func firstCwd(in url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunk = (try? handle.read(upToCount: 8192)) ?? Data()
        guard let text = String(data: chunk, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cwd = json["cwd"] as? String, !cwd.isEmpty else { continue }
            return cwd
        }
        return nil
    }
}
