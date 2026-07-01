// ClaudeMonitor/Data/UpdateChecker.swift
import Foundation
import Combine

/// 시맨틱 버전 비교 (순수).
enum SemVer {
    /// remote 가 local 보다 새 버전이면 true. 숫자 단위로 비교(문자열 비교 아님).
    static func isNewer(_ remote: String, than local: String) -> Bool {
        guard remote.contains(where: \.isNumber) else { return false }
        let r = parts(remote), l = parts(local)
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    private static func parts(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}

/// GitHub main 의 Info.plist 버전을 읽어 현재 실행 버전과 비교, 업데이트 여부를 알린다.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var latestVersion: String?
    @Published private(set) var updateAvailable = false

    let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    /// 릴리스가 없어 main 브랜치의 Info.plist 버전을 기준으로 삼는다.
    private let manifestURL = URL(string: "https://raw.githubusercontent.com/xivicWon/ai-usage-snipping/main/ClaudeMonitor/Info.plist")!
    /// 업데이트 안내 클릭 시 열 페이지.
    static let repoURL = URL(string: "https://github.com/xivicWon/ai-usage-snipping")!

    private init() {}

    /// 원격 버전을 가져와 비교한다. 실패는 조용히 무시.
    func check() {
        var req = URLRequest(url: manifestURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8),
                  let remote = Self.parseVersion(fromInfoPlist: text) else { return }
            DispatchQueue.main.async {
                self.latestVersion = remote
                self.updateAvailable = SemVer.isNewer(remote, than: self.currentVersion)
            }
        }.resume()
    }

    /// Info.plist 텍스트에서 CFBundleShortVersionString 값을 추출.
    static func parseVersion(fromInfoPlist text: String) -> String? {
        guard let range = text.range(of: "CFBundleShortVersionString") else { return nil }
        let tail = text[range.upperBound...]
        guard let open = tail.range(of: "<string>"),
              let close = tail.range(of: "</string>") else { return nil }
        return String(tail[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
