// ClaudeMonitor/App/ClaudeMonitorApp.swift
import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            // 메뉴바 타이틀: 비용이 0이면 $0.00, 아니면 포맷된 금액
            Text(appState.todayCostUSD == 0
                 ? "$0.00"
                 : appState.todayCostUSD.formatted(.currency(code: "USD")))
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)

        Window("대시보드", id: "dashboard") {
            Text("Dashboard — Phase 2에서 구현")  // 플레이스홀더
                .frame(width: 700, height: 500)
                .environmentObject(appState)
        }
        .windowResizability(.contentMinSize)
    }
}
