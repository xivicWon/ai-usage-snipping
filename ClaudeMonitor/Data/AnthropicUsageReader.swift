// ClaudeMonitor/Data/AnthropicUsageReader.swift
import Foundation
import Combine

struct AnthropicUsage {
    var fiveHourPercentUsed: Int       // 0–100, percent USED
    var weeklyPercentUsed: Int         // 0–100, percent USED
    var fiveHourResetsAt: Date?
    var weeklyResetsAt: Date?
    var extraUsageSpentUSD: Double
    var extraUsageLimitUSD: Double
    var fetchedAt: Date

    var fiveHourRemaining: Double { max(0, Double(100 - fiveHourPercentUsed)) / 100 }
    var weeklyRemaining: Double   { max(0, Double(100 - weeklyPercentUsed)) / 100 }

    func timeUntilReset(_ date: Date?) -> String? {
        guard let date else { return nil }
        let diff = date.timeIntervalSinceNow
        guard diff > 0 else { return "곧 갱신" }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        let cal = Calendar.current

        // Relative part
        let relative: String
        if diff < 3600 {
            relative = String(format: "%.0f분 후", diff / 60)
        } else {
            relative = String(format: "%.0f시간 %.0f분 후", floor(diff / 3600), (diff.truncatingRemainder(dividingBy: 3600)) / 60)
        }

        // Absolute part
        fmt.dateFormat = cal.isDateInToday(date) ? "a h:mm" : "M/d a h:mm"
        let absolute = fmt.string(from: date)

        return "\(relative) · \(absolute)"
    }
}

/// Reads the OMC usage cache that already contains real Anthropic quota percentages.
final class AnthropicUsageReader: ObservableObject {
    static let shared = AnthropicUsageReader()

    @Published private(set) var usage: AnthropicUsage?
    @Published private(set) var cacheAge: String = ""

    private let cachePath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/plugins/oh-my-claudecode/.usage-cache-anthropic.json")

    private var watcher: DispatchSourceFileSystemObject?
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {
        reload()
        startWatching()
    }

    func reload() {
        guard let data = try? Data(contentsOf: cachePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = json["data"] as? [String: Any],
              (json["error"] as? Bool) == false
        else { return }

        let fiveHourPct  = inner["fiveHourPercent"]  as? Int ?? 0
        let weeklyPct    = inner["weeklyPercent"]     as? Int ?? 0
        let fiveResetStr = inner["fiveHourResetsAt"]  as? String
        let weekResetStr = inner["weeklyResetsAt"]    as? String
        let spentUSD     = inner["extraUsageSpentUsd"] as? Double ?? 0
        let limitUSD     = inner["extraUsageLimitUsd"] as? Double ?? 0

        let timestampMs = json["timestamp"] as? Double ?? 0
        let fetchedAt   = Date(timeIntervalSince1970: timestampMs / 1000)

        let newUsage = AnthropicUsage(
            fiveHourPercentUsed: fiveHourPct,
            weeklyPercentUsed:   weeklyPct,
            fiveHourResetsAt:    fiveResetStr.flatMap { iso.date(from: $0) },
            weeklyResetsAt:      weekResetStr.flatMap { iso.date(from: $0) },
            extraUsageSpentUSD:  spentUSD,
            extraUsageLimitUSD:  limitUSD,
            fetchedAt:           fetchedAt
        )

        DispatchQueue.main.async {
            self.usage = newUsage
            let age = Int(Date().timeIntervalSince(fetchedAt) / 60)
            self.cacheAge = age < 2 ? "방금 전" : "\(age)분 전"
        }
    }

    private func startWatching() {
        let fd = open(cachePath.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .global(qos: .utility)
        )
        src.setEventHandler { [weak self] in self?.reload() }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }
}
