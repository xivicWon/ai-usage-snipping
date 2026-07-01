// ClaudeMonitor/Data/RetroNotifier.swift
import Foundation
import UserNotifications

/// 새 회고 생성 시 macOS 알림(포인터)을 발송한다. 내용은 담지 않고 CM 으로 유도.
final class RetroNotifier {
    static let shared = RetroNotifier()
    static let deeplinkKey = "cm.deeplink"
    static let deeplinkRetro = "retro"

    private init() {}

    /// 최초 1회 권한 요청.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// "새 회고가 생성되었습니다" 배너 — 클릭 시 회고 탭으로 딥링크.
    func notifyNewRetrospective(periodLabel: String) {
        let content = UNMutableNotificationContent()
        content.title = "새 회고가 생성되었습니다"
        content.body = "\(periodLabel) 사용패턴 회고 — 대시보드에서 확인하세요"
        content.sound = .default
        content.userInfo = [Self.deeplinkKey: Self.deeplinkRetro]
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

/// 딥링크로 대시보드가 특정 탭을 열도록 요청하는 공유 라우터.
final class DashboardRouter: ObservableObject {
    static let shared = DashboardRouter()
    /// 대시보드가 감시하다가 값이 오면 해당 탭으로 전환하고 nil 로 되돌린다.
    @Published var requestedTool: String?
    private init() {}
}

/// "새 회고 미확인" 배지 상태 — OS 알림 대신 메뉴바/탭에 점으로 표시(서명 무관).
/// 마지막으로 본 회고 시각과 최신 회고를 비교한다.
final class RetroBadge: ObservableObject {
    static let shared = RetroBadge()
    @Published private(set) var hasUnseen = false

    private let store = try? RetrospectiveReportStore(path: RetrospectiveReportStore.defaultPath())
    private let key = "retro_last_seen"

    private init() { refresh() }

    /// 최신 회고가 마지막으로 본 것보다 새로우면 배지 켬.
    func refresh() {
        guard let latest = try? store?.latest() ?? nil else { hasUnseen = false; return }
        let lastSeen = UserDefaults.standard.double(forKey: key)
        hasUnseen = latest.generatedAt.timeIntervalSince1970 > lastSeen + 0.5
    }

    /// 회고 탭을 열었을 때 호출 — 최신 회고를 본 것으로 표시.
    func markSeen() {
        if let latest = try? store?.latest() ?? nil {
            UserDefaults.standard.set(latest.generatedAt.timeIntervalSince1970, forKey: key)
        }
        hasUnseen = false
    }
}

/// "새 조언 미확인" 배지 — 라이브 어드바이저용(RetroBadge 패턴, 서명 무관).
final class AdvisorBadge: ObservableObject {
    static let shared = AdvisorBadge()
    @Published private(set) var hasUnseen = false

    private let store = try? AdvisorAdviceStore(path: AdvisorAdviceStore.defaultPath())
    private let key = "advisor_last_seen"

    private init() { refresh() }

    /// 최신 조언이 마지막으로 본 것보다 새로우면 배지 켬.
    func refresh() {
        guard let latest = try? store?.latest() ?? nil else { hasUnseen = false; return }
        let lastSeen = UserDefaults.standard.double(forKey: key)
        hasUnseen = latest.generatedAt.timeIntervalSince1970 > lastSeen + 0.5
    }

    /// 조언 탭을 열었을 때 호출 — 최신 조언을 본 것으로 표시.
    func markSeen() {
        if let latest = try? store?.latest() ?? nil {
            UserDefaults.standard.set(latest.generatedAt.timeIntervalSince1970, forKey: key)
        }
        hasUnseen = false
    }
}
