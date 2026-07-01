// ClaudeMonitor/Data/LiveAdvisorEngine.swift
import Foundation

/// 라이브 어드바이저 오케스트레이터.
/// 매 주기: 신호 → 순수 감지(AdvisorDetector) → 트리거 시에만 `claude -p` 1콜 → 저장.
/// 감지 상태(streak/쿨다운)는 메모리로 들고 다닌다.
final class LiveAdvisorEngine {
    private let store: AdvisorAdviceStore
    private let generate: (String) throws -> String   // 프롬프트 → 조언 본문 (claude -p 주입)
    private let now: () -> Date
    private let advanceClock: (TimeInterval) -> Void   // 테스트 전용(실사용은 no-op, 벽시계 사용)
    private let makeId: () -> String
    private let config: AdvisorConfig

    private(set) var state = AdvisorState()

    init(store: AdvisorAdviceStore,
         generate: @escaping (String) throws -> String,
         now: @escaping () -> Date = Date.init,
         advanceClock: @escaping (TimeInterval) -> Void = { _ in },
         makeId: @escaping () -> String = { UUID().uuidString },
         config: AdvisorConfig = .default) {
        self.store = store
        self.generate = generate
        self.now = now
        self.advanceClock = advanceClock
        self.makeId = makeId
        self.config = config
    }

    /// 이번 체크를 수행한다. 트리거되면 조언을 생성·저장하고 반환, 아니면 nil.
    /// 트리거되지 않으면 `generate`(=claude -p)는 절대 호출하지 않는다(토큰 0).
    @discardableResult
    func check(signals: AdvisorSignals, intervalMinutes: Int) -> AdvisorAdvice? {
        advanceClock(Double(intervalMinutes) * 60)
        let (newState, triggered) = AdvisorDetector.evaluate(
            current: signals, now: now(), state: state, config: config)
        state = newState
        guard let condition = triggered else { return nil }

        let prompt = AdvisorPromptBuilder.build(condition: condition, signals: signals)
        guard let body = try? generate(prompt), !body.isEmpty else { return nil }

        let advice = AdvisorAdvice(id: makeId(), condition: condition.rawValue,
                                   generatedAt: now(), body: body)
        try? store.save(advice)
        return advice
    }
}
