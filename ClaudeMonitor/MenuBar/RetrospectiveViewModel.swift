// ClaudeMonitor/MenuBar/RetrospectiveViewModel.swift
import Foundation
import Combine

/// 대시보드 회고 탭의 상태. 엔진(생성)과 리포트 스토어(히스토리)를 소유한다.
final class RetrospectiveViewModel: ObservableObject {
    @Published var reports: [RetrospectiveReport] = []
    @Published var selected: RetrospectiveReport?
    @Published var period: RetroPeriod = .week
    @Published var style: RetroStyle = .standard
    @Published var isGenerating = false
    @Published var errorMessage: String?

    private let reportStore: RetrospectiveReportStore?
    private let engine: RetrospectiveEngine?

    init() {
        let rs = try? RetrospectiveReportStore(path: RetrospectiveReportStore.defaultPath())
        let fs = try? SessionFeatureStore(path: SessionFeatureStore.defaultPath())
        reportStore = rs
        if let rs, let fs {
            let runner = ClaudeHeadlessRunner(runner: ProcessCommandRunner())
            engine = RetrospectiveEngine(featureStore: fs, reportStore: rs,
                                         generate: { try runner.run(prompt: $0, timeout: 180) })
        } else {
            engine = nil
        }
        loadHistory()
    }

    var isAvailable: Bool { engine != nil }

    func loadHistory() {
        let loaded = (try? reportStore?.all()) ?? []
        reports = loaded
        if selected == nil { selected = loaded.first }
    }

    func generateNow() {
        guard let engine, !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        let period = self.period
        let style = self.style
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let report = try engine.generate(period: period, style: style)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isGenerating = false
                    self.loadHistory()
                    self.selected = report
                    RetroBadge.shared.markSeen()   // 방금 만든 걸 보고 있으니 확인 처리
                }
            } catch {
                let msg: String
                if case RetrospectiveEngine.GenerateError.noActivity = error {
                    msg = "이 기간에 분석할 사람 세션이 없습니다."
                } else {
                    msg = "회고 생성에 실패했습니다. (claude -p 사용 가능 여부 확인)"
                }
                DispatchQueue.main.async {
                    self?.isGenerating = false
                    self?.errorMessage = msg
                }
            }
        }
    }
}
