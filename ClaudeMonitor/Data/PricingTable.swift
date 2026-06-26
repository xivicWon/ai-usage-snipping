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
