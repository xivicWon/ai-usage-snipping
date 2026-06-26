// ClaudeMonitor/MenuBar/MenuBarView.swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 요약 헤더
            HStack(spacing: 16) {
                statBlock(label: "오늘", value: appState.todayCostUSD.formatted(.currency(code: "USD")))
                Divider().frame(height: 32)
                statBlock(label: "이번 주", value: appState.weekCostUSD.formatted(.currency(code: "USD")))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Text("\(appState.todayTokens.formatted()) tokens")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Divider()

            Button {
                openWindow(id: "dashboard")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("대시보드 열기", systemImage: "chart.bar")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("종료")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 220)
    }

    private func statBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.title3.monospacedDigit().bold())
        }
    }
}
