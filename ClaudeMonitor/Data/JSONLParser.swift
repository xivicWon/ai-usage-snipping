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
        guard offset < data.count else { return [] }

        let slice = data[offset...]
        guard let text = String(data: slice, encoding: .utf8) else { return [] }

        // Advance only to the last newline boundary to avoid consuming partial lines.
        // Bytes after the last newline stay in the "unread" buffer for the next call.
        let lastNewlineOffset: Int
        if let lastNL = slice.lastIndex(of: UInt8(ascii: "\n")) {
            lastNewlineOffset = slice.distance(from: slice.startIndex, to: lastNL) + 1
        } else {
            // No newline yet — entire slice may be a partial line; don't advance
            return []
        }
        offsets[path] = offset + lastNewlineOffset

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
