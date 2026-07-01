// ClaudeMonitor/Data/NewsNotifier.swift
import Foundation
import UserNotifications

/// 새 뉴스 다이제스트 생성 시 macOS 알림(포인터)을 발송한다. 내용은 담지 않고 CM 으로 유도.
final class NewsNotifier {
    static let shared = NewsNotifier()
    static let deeplinkKey = "cm.deeplink"
    static let deeplinkNews = "📰 뉴스"   // DashboardView.AITool.news.rawValue 와 일치

    private init() {}

    /// "새 뉴스 요약이 준비되었습니다" 배너 — 클릭 시 뉴스 탭으로 딥링크.
    func notifyNewDigest() {
        let content = UNMutableNotificationContent()
        content.title = "새 AI 뉴스 요약이 준비되었습니다"
        content.body = "오늘의 한줄요약 — 대시보드에서 확인하세요"
        content.sound = .default
        content.userInfo = [Self.deeplinkKey: Self.deeplinkNews]
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

/// "새 뉴스 미확인" 배지 상태 — OS 알림 대신 메뉴바/탭에 점으로 표시(서명 무관).
/// 마지막으로 본 다이제스트 시각과 최신 다이제스트를 비교한다.
final class NewsBadge: ObservableObject {
    static let shared = NewsBadge()
    @Published private(set) var hasUnseen = false

    private let store = try? NewsDigestStore(path: NewsDigestStore.defaultPath())
    private let key = "news_last_seen"

    private init() { refresh() }

    /// 최신 다이제스트가 마지막으로 본 것보다 새로우면 배지 켬.
    func refresh() {
        guard let latest = try? store?.latest() ?? nil else { hasUnseen = false; return }
        let lastSeen = UserDefaults.standard.double(forKey: key)
        hasUnseen = latest.generatedAt.timeIntervalSince1970 > lastSeen + 0.5
    }

    /// 뉴스 탭을 열었을 때 호출 — 최신 다이제스트를 본 것으로 표시.
    func markSeen() {
        if let latest = try? store?.latest() ?? nil {
            UserDefaults.standard.set(latest.generatedAt.timeIntervalSince1970, forKey: key)
        }
        hasUnseen = false
    }
}
