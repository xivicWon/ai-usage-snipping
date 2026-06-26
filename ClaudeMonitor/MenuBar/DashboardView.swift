// ClaudeMonitor/MenuBar/DashboardView.swift
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var sessions = SessionReader.shared
    @ObservedObject private var usageReader = AnthropicUsageReader.shared

    var body: some View {
        HSplitView {
            sessionSidebar
                .frame(minWidth: 180, maxWidth: 220)
            usageContent
        }
        .frame(width: 740, height: 520)
    }

    // MARK: - Session sidebar

    private var sessionSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Account header
            HStack(spacing: 6) {
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    let email = UsageLimits.shared.accountEmail
                    Text(email.isEmpty ? "계정 미설정" : email)
                        .font(.headline)
                    if let sub = sessions.accountInfo?.subscriptionType, !sub.isEmpty {
                        Text((sessions.accountInfo?.displayPlan ?? "") + " 플랜")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            // Session stats
            HStack(spacing: 0) {
                statChip(value: "\(sessions.activeCount)", label: "활성", color: .green)
                statChip(value: "\(sessions.idleSessions.count)", label: "대기", color: .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            Text("세션")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 4)

            List(sessions.sessions) { session in
                sessionRow(session)
                    .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                sessions.reload()
            } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func sessionRow(_ s: ClaudeSession) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(s.isActive ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.projectName)
                    .font(.caption.weight(s.isActive ? .semibold : .regular))
                    .lineLimit(1)
                Text(s.duration)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func statChip(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 3)
    }

    // MARK: - Usage content

    private var usageContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 28) {
                summaryCard(title: "5시간 창", pct: appState.windowPercentRemaining,
                            reset: usageReader.usage?.timeUntilReset(usageReader.usage?.fiveHourResetsAt))
                summaryCard(title: "이번 주", pct: appState.weeklyPercentRemaining,
                            reset: usageReader.usage?.timeUntilReset(usageReader.usage?.weeklyResetsAt))
                summaryCard(title: "오늘 비용", pct: nil, cost: appState.todayCostUSD, reset: nil)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            if appState.dailySummaries.isEmpty {
                Spacer()
                Text("데이터 없음").foregroundStyle(.secondary)
                Spacer()
            } else {
                Table(appState.dailySummaries) {
                    TableColumn("날짜", value: \.date)
                    TableColumn("입력") { row in
                        Text(fmt(row.totalInputTokens)).monospacedDigit()
                    }.width(75)
                    TableColumn("출력") { row in
                        Text(fmt(row.totalOutputTokens)).monospacedDigit()
                    }.width(75)
                    TableColumn("합계") { row in
                        Text(fmt(row.totalInputTokens + row.totalOutputTokens)).monospacedDigit().bold()
                    }.width(80)
                    TableColumn("비용") { row in
                        Text(row.totalCostUSD.formatted(.currency(code: "USD"))).monospacedDigit()
                    }.width(80)
                    TableColumn("세션") { row in
                        Text("\(row.sessionCount)").monospacedDigit()
                    }.width(45)
                }
            }
        }
    }

    private func summaryCard(title: String, pct: Double?, cost: Double? = nil, reset: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            if let pct {
                Text(String(format: "%.0f%%", pct * 100))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(pctColor(pct))
                if let r = reset { Text(r).font(.system(size: 9)).foregroundStyle(.tertiary) }
            } else if let cost {
                Text(cost.formatted(.currency(code: "USD")))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
            }
        }
    }

    private func pctColor(_ pct: Double) -> Color {
        switch pct {
        case 0.5...: return .green
        case 0.2..<0.5: return .orange
        default: return .red
        }
    }

    private func fmt(_ n: Int) -> String {
        switch n {
        case 0..<1_000: return "\(n)"
        case 1_000..<1_000_000: return String(format: "%.1fK", Double(n)/1_000)
        default: return String(format: "%.1fM", Double(n)/1_000_000)
        }
    }
}
