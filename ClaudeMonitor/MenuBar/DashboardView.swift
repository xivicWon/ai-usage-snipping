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
        .frame(width: 760, height: 480)
    }

    // MARK: - Session sidebar

    private var sessionSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                statChip(value: "\(sessions.activeCount)", label: "활성", color: .green)
                statChip(value: "\(sessions.idleSessions.count)", label: "대기", color: .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Divider()

            Text("세션")
                .font(.caption2).foregroundStyle(.tertiary).textCase(.uppercase)
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)

            List(sessions.sessions) { session in
                sessionRow(session)
                    .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
            }
            .listStyle(.sidebar)

            Divider()

            Button { sessions.reload() } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
                    .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 8)
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
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    private func statChip(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
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
            // Usage summary cards
            HStack(spacing: 28) {
                summaryCard(title: "5시간 창",
                            pct: appState.windowPercentRemaining,
                            reset: usageReader.usage?.timeUntilReset(usageReader.usage?.fiveHourResetsAt))
                summaryCard(title: "이번 주",
                            pct: appState.weeklyPercentRemaining,
                            reset: usageReader.usage?.timeUntilReset(usageReader.usage?.weeklyResetsAt))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Weekly project breakdown
            weeklyProjectChart
        }
    }

    private func summaryCard(title: String, pct: Double?, reset: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2).foregroundStyle(.tertiary).textCase(.uppercase)
            if let pct {
                Text(String(format: "%.0f%%", pct * 100))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(pctColor(pct))
                if let r = reset {
                    Text(r).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Project chart

    private var weeklyProjectChart: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("이번 주 프로젝트별 사용량")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(weekRangeLabel())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if appState.weeklyProjects.isEmpty {
                Spacer()
                Text("데이터 없음").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                let maxTokens = appState.weeklyProjects.first?.totalTokens ?? 1
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(appState.weeklyProjects) { proj in
                            projectBar(proj, maxTokens: maxTokens)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func projectBar(_ proj: ProjectSummary, maxTokens: Int) -> some View {
        let ratio = Double(proj.totalTokens) / Double(maxTokens)
        let barColor: Color = ratio > 0.6 ? .orange : .blue

        return HStack(spacing: 8) {
            Text(proj.projectName)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor.opacity(0.75))
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 14)

            Text(fmtTokens(proj.totalTokens))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private func weekRangeLabel() -> String {
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now)
        // Monday = 2 in Calendar (Sun=1), offset to get Mon
        let daysFromMon = (weekday + 5) % 7
        guard let mon = cal.date(byAdding: .day, value: -daysFromMon, to: now),
              let sun = cal.date(byAdding: .day, value: 6 - daysFromMon, to: now) else {
            return ""
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return "\(fmt.string(from: mon)) – \(fmt.string(from: sun))"
    }

    private func pctColor(_ pct: Double) -> Color {
        switch pct {
        case 0.5...: return .green
        case 0.2..<0.5: return .orange
        default: return .red
        }
    }

    private func fmtTokens(_ n: Int) -> String {
        switch n {
        case 0..<1_000: return "\(n)"
        case 1_000..<1_000_000: return String(format: "%.1fK", Double(n)/1_000)
        default: return String(format: "%.1fM", Double(n)/1_000_000)
        }
    }
}
