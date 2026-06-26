// ClaudeMonitor/Data/SessionReader.swift
import Foundation
import Combine

struct ClaudeSession: Identifiable {
    var id: String          // sessionId
    var projectName: String  // last path component of cwd
    var cwd: String
    var status: String       // "busy" | "idle"
    var startedAt: Date
    var updatedAt: Date

    var isActive: Bool { status == "busy" }

    var duration: String {
        let secs = Date().timeIntervalSince(startedAt)
        if secs < 3600 { return String(format: "%.0f분", secs / 60) }
        return String(format: "%.1f시간", secs / 3600)
    }
}

final class SessionReader: ObservableObject {
    static let shared = SessionReader()

    @Published private(set) var sessions: [ClaudeSession] = []

    private let sessionsURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/sessions")
    private var timer: Timer?

    private init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.reload()
        }
    }

    // MARK: - Sessions

    func reload() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: sessionsURL, includingPropertiesForKeys: nil
        ) else { return }

        let loaded: [ClaudeSession] = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }

                let sessionId = json["sessionId"] as? String ?? url.deletingPathExtension().lastPathComponent
                let cwd       = json["cwd"] as? String ?? ""
                let status    = json["status"] as? String ?? "idle"
                let startMs   = json["startedAt"] as? Double ?? 0
                let updMs     = json["updatedAt"] as? Double ?? startMs

                return ClaudeSession(
                    id: sessionId,
                    projectName: URL(fileURLWithPath: cwd).lastPathComponent,
                    cwd: cwd,
                    status: status,
                    startedAt: Date(timeIntervalSince1970: startMs / 1000),
                    updatedAt: Date(timeIntervalSince1970: updMs / 1000)
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }

        DispatchQueue.main.async { self.sessions = loaded }
    }

    var activeSessions:  [ClaudeSession] { sessions.filter(\.isActive) }
    var idleSessions:    [ClaudeSession] { sessions.filter { !$0.isActive } }
    var activeCount: Int { activeSessions.count }
}
