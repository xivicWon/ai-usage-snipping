// ClaudeMonitor/Data/ClaudeSessionFeatureParser.swift
import Foundation

/// Claude Code 트랜스크립트(`~/.claude/projects/*.jsonl`) 한 파일 →
/// 세션 단위 파생 신호(`SessionFeatures`). 원문은 저장하지 않는다.
final class ClaudeSessionFeatureParser {

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    /// 파일을 통째로 읽어 세션 피처 1개로 환원한다. 유효 데이터가 없으면 nil.
    func parse(_ fileURL: URL) throws -> SessionFeatures? {
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        var sessionId = "", projectPath = ""
        var goalCount = 0, errorCount = 0, interruptCount = 0, totalTokens = 0
        var toolCounts: [String: Int] = [:]
        var filesEdited: [String] = []
        var seenFiles = Set<String>()
        var testTouched = false
        var startedAt: Date?, endedAt: Date?
        var sawAnyLine = false

        for line in text.components(separatedBy: "\n") {
            guard let lineData = line.data(using: .utf8), !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            sawAnyLine = true

            if sessionId.isEmpty, let s = obj["sessionId"] as? String { sessionId = s }
            if projectPath.isEmpty, let c = obj["cwd"] as? String { projectPath = c }
            if let d = Self.parseDate(obj["timestamp"] as? String) {
                if startedAt == nil { startedAt = d }
                endedAt = d
            }

            let type = obj["type"] as? String
            let msg = obj["message"] as? [String: Any]

            if type == "user" {
                let content = msg?["content"]
                let (texts, toolResults) = Self.userBlocks(content)
                if !toolResults.isEmpty {
                    errorCount += toolResults.filter { $0 }.count   // is_error == true
                    continue                                        // 도구결과는 goal 아님
                }
                let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if joined.contains("[Request interrupted by user]") {
                    interruptCount += 1
                } else if joined.isEmpty
                            || joined.hasPrefix("<")
                            || joined.hasPrefix("Base directory for this skill") {
                    // 메타/스킬 주입 — goal 아님
                } else {
                    goalCount += 1
                }
            } else if type == "assistant" {
                if let usage = msg?["usage"] as? [String: Any] {
                    totalTokens += (usage["input_tokens"] as? Int ?? 0) + (usage["output_tokens"] as? Int ?? 0)
                }
                if let content = msg?["content"] as? [[String: Any]] {
                    for block in content where block["type"] as? String == "tool_use" {
                        let name = block["name"] as? String ?? "?"
                        toolCounts[name, default: 0] += 1
                        if name == "Edit" || name == "Write" || name == "NotebookEdit",
                           let input = block["input"] as? [String: Any],
                           let path = (input["file_path"] as? String) ?? (input["notebook_path"] as? String) {
                            if seenFiles.insert(path).inserted { filesEdited.append(path) }
                            let low = path.lowercased()
                            if low.contains("test") || low.contains("spec") { testTouched = true }
                        }
                    }
                }
            }
        }

        guard sawAnyLine else { return nil }
        return SessionFeatures(
            sessionId: sessionId, source: "claude", projectPath: projectPath,
            goalCount: goalCount, toolCounts: toolCounts, filesEdited: filesEdited,
            testTouched: testTouched, errorCount: errorCount, interruptCount: interruptCount,
            totalTokens: totalTokens, startedAt: startedAt, endedAt: endedAt
        )
    }

    /// user content(String 또는 블록 배열) → (텍스트들, tool_result 의 is_error 플래그들)
    private static func userBlocks(_ content: Any?) -> (texts: [String], toolResults: [Bool]) {
        if let s = content as? String { return ([s], []) }
        guard let arr = content as? [[String: Any]] else { return ([], []) }
        var texts: [String] = [], results: [Bool] = []
        for b in arr {
            switch b["type"] as? String {
            case "text": if let t = b["text"] as? String { texts.append(t) }
            case "tool_result": results.append(b["is_error"] as? Bool ?? false)
            default: break
            }
        }
        return (texts, results)
    }
}
