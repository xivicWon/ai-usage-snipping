// ClaudeMonitor/Data/AdvisorDetector.swift
import Foundation

/// 매 체크마다 읽는 라이브 신호. 토큰 0(로컬·무료)로 얻는다.
/// - SessionFeatures(현재 세션): totalTokens·filesEdited·errorCount
/// - hud-cache.json(AnthropicUsage): five_hour used_percentage
struct AdvisorSignals: Equatable {
    var totalTokens: Int
    var filesEditedCount: Int
    var errorCount: Int
    /// 5시간 창 소진율(0–100). 모르면 nil.
    var fiveHourPercentUsed: Int?
}

/// v1 트리거 조건. 라벨은 프롬프트·UI 에 노출.
enum AdvisorCondition: String, CaseIterable, Identifiable {
    case stuck              // 막힘: 토큰 급증 + 편집 0
    case errorRepeat        // 에러 반복: errorCount 연속 증가
    case rateLimitImminent  // 한도 임박: 5h 소진 ETA < 임계

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stuck:             return "막힘 감지"
        case .errorRepeat:       return "에러 반복"
        case .rateLimitImminent: return "한도 임박"
        }
    }

    /// 상황 설명 — 프롬프트/조언 헤더에 쓰는 한 줄.
    var summary: String {
        switch self {
        case .stuck:             return "토큰은 계속 늘어나는데 파일 편집이 없습니다(막힘 신호)."
        case .errorRepeat:       return "도구 에러가 연속으로 증가하고 있습니다."
        case .rateLimitImminent: return "5시간 사용 한도 소진이 임박했습니다."
        }
    }
}

/// 감지 튜닝값. 기본값은 이슈 스펙(K=2, 쿨다운 30분).
struct AdvisorConfig: Equatable {
    var consecutiveK: Int = 2        // 연속 K회 지속해야 트리거
    var cooldownMinutes: Double = 30 // 트리거 후 쿨다운
    var stuckTokenDelta: Int = 5_000 // "토큰 크게 늘었다" 임계
    var rateETAMinutes: Double = 30  // 소진 ETA 임박 임계

    static let `default` = AdvisorConfig()
}

/// 순수 감지의 누적 상태. 직렬화 없이 엔진이 메모리로 들고 다닌다.
struct AdvisorState: Equatable {
    var previous: AdvisorSignals?
    var previousAt: Date?
    var stuckStreak: Int = 0
    var errorStreak: Int = 0
    var rateStreak: Int = 0
    var lastTriggeredAt: Date?
}

/// 라이브 어드바이저의 심장 — 순수 감지 규칙.
/// (현재 신호, 이전 상태) → (다음 상태, 트리거된 조건?)
/// 반복 판정(연속 K회) + 쿨다운 + 이중발사 방지.
enum AdvisorDetector {
    static func evaluate(current: AdvisorSignals, now: Date,
                         state: AdvisorState, config: AdvisorConfig = .default)
        -> (state: AdvisorState, triggered: AdvisorCondition?) {
        var s = state

        var stuckActive = false, errorActive = false, rateActive = false
        if let prev = state.previous {
            let tokenDelta = current.totalTokens - prev.totalTokens
            let filesDelta = current.filesEditedCount - prev.filesEditedCount
            stuckActive = tokenDelta >= config.stuckTokenDelta && filesDelta == 0
            errorActive = current.errorCount > prev.errorCount
            rateActive  = rateImminent(prev: prev, current: current,
                                       prevAt: state.previousAt, now: now, config: config)
        }

        // 활성이면 +1, 아니면 리셋(반복이 끊기면 스트릭 소멸).
        s.stuckStreak = stuckActive ? s.stuckStreak + 1 : 0
        s.errorStreak = errorActive ? s.errorStreak + 1 : 0
        s.rateStreak  = rateActive  ? s.rateStreak  + 1 : 0

        let cooldownOK: Bool = {
            guard let last = state.lastTriggeredAt else { return true }
            return now.timeIntervalSince(last) >= config.cooldownMinutes * 60
        }()

        // 우선순위: 한도 임박(가장 시급) > 막힘 > 에러 반복.
        var triggered: AdvisorCondition?
        if cooldownOK {
            if s.rateStreak >= config.consecutiveK {
                triggered = .rateLimitImminent
            } else if s.stuckStreak >= config.consecutiveK {
                triggered = .stuck
            } else if s.errorStreak >= config.consecutiveK {
                triggered = .errorRepeat
            }
        }

        if let t = triggered {
            s.lastTriggeredAt = now
            switch t {   // 발사한 조건만 스트릭 리셋 — 쿨다운 후 재축적
            case .rateLimitImminent: s.rateStreak = 0
            case .stuck:             s.stuckStreak = 0
            case .errorRepeat:       s.errorStreak = 0
            }
        }

        s.previous = current
        s.previousAt = now
        return (s, triggered)
    }

    /// 5h 소진 기울기(%/분)로 ETA 를 추정해 임박 여부 판정.
    private static func rateImminent(prev: AdvisorSignals, current: AdvisorSignals,
                                     prevAt: Date?, now: Date, config: AdvisorConfig) -> Bool {
        guard let used = current.fiveHourPercentUsed else { return false }
        if used >= 100 { return true }
        guard let prevUsed = prev.fiveHourPercentUsed, let prevAt else { return false }
        let minutes = now.timeIntervalSince(prevAt) / 60
        guard minutes > 0 else { return false }
        let slope = Double(used - prevUsed) / minutes   // %/분
        guard slope > 0 else { return false }
        let eta = Double(100 - used) / slope
        return eta < config.rateETAMinutes
    }
}

/// 어드바이저 주기 도래 판정 — 순수 함수(RetrospectiveScheduler 패턴).
enum AdvisorScheduler {
    static func isDue(enabled: Bool, intervalMinutes: Int, lastCheckedAt: Date?, now: Date) -> Bool {
        guard enabled, intervalMinutes > 0 else { return false }
        guard let last = lastCheckedAt else { return true }
        return now.timeIntervalSince(last) >= Double(intervalMinutes) * 60
    }
}
