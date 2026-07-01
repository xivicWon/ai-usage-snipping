// ClaudeMonitor/MenuBar/NewsViewModel.swift
import Foundation
import Combine

/// 대시보드 뉴스 탭의 상태. 엔진(생성)과 다이제스트 스토어(히스토리)를 소유한다.
final class NewsViewModel: ObservableObject {
    @Published var digests: [NewsDigest] = []
    @Published var selected: NewsDigest?
    @Published var isGenerating = false
    @Published var errorMessage: String?

    private let store: NewsDigestStore?
    private let engine: NewsDigestEngine?

    init() {
        let st = try? NewsDigestStore(path: NewsDigestStore.defaultPath())
        store = st
        if let st {
            let runner = ClaudeHeadlessRunner(runner: ProcessCommandRunner())
            engine = NewsDigestEngine(
                store: st,
                fetch: { URLSessionFeedFetcher.fetch($0) },
                generate: { try runner.run(prompt: $0, timeout: 180) })
        } else {
            engine = nil
        }
        loadHistory()
    }

    var isAvailable: Bool { engine != nil }

    func loadHistory() {
        let loaded = (try? store?.all()) ?? []
        digests = loaded
        if selected == nil { selected = loaded.first }
    }

    func generateNow() {
        guard let engine, !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let digest = try engine.generate()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isGenerating = false
                    self.loadHistory()
                    self.selected = digest
                    NewsBadge.shared.markSeen()   // 방금 만든 걸 보고 있으니 확인 처리
                }
            } catch {
                let msg: String
                if case NewsDigestEngine.GenerateError.noItems = error {
                    msg = "가져올 수 있는 뉴스가 없습니다. (네트워크/소스 확인)"
                } else {
                    msg = "뉴스 요약 생성에 실패했습니다. (claude -p 사용 가능 여부 확인)"
                }
                DispatchQueue.main.async {
                    self?.isGenerating = false
                    self?.errorMessage = msg
                }
            }
        }
    }
}
