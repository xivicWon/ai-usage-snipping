// ClaudeMonitor/MenuBar/MenuBarView.swift
import SwiftUI

// MARK: - Menu item row (tap gesture — never receives keyboard focus)

struct MenuItemRow: View {
    let label: String
    let icon: String?
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Group {
            if let icon {
                Label(label, systemImage: icon)
            } else {
                Text(label)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isPressed
                      ? Color.accentColor.opacity(0.15)
                      : isHovered ? Color.secondary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false; action() }
        )
        .animation(.easeInOut(duration: 0.08), value: isHovered)
        .animation(.easeInOut(duration: 0.08), value: isPressed)
    }
}

// MARK: - Token rate gauge (stacked bars: 0 미사용 → 3 폭발적)

struct UsageGauge: View {
    let level: Int   // 0–3

    var body: some View {
        VStack(spacing: 1.5) {
            bar(active: level >= 3, color: .red)
            bar(active: level >= 2, color: .orange)
            bar(active: level >= 1, color: .green)
        }
    }

    private func bar(active: Bool, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(active ? color : Color.secondary.opacity(0.15))
            .frame(width: 5, height: 3)
    }
}

// MARK: - Water tank gauge (vertical, drains from top)

struct WaterTankView: View {
    let pct: Double   // 0.0–1.0 remaining
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.1))
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.8))
                    .frame(height: geo.size.height * pct)
                    .animation(.easeInOut(duration: 0.6), value: pct)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Main view

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var usageReader = AnthropicUsageReader.shared
    @ObservedObject private var sessions   = SessionReader.shared
    @ObservedObject private var codexReader = CodexSessionReader.shared
    @ObservedObject private var limits     = UsageLimits.shared
    let openDashboard: () -> Void
    let openSettings: () -> Void

    // 실제 데이터가 들어오는지(=연결됨) 여부 — 헤더의 상태 점으로만 표시한다.
    private var isClaudeConnected: Bool { usageReader.usage != nil }
    private var isCodexConnected: Bool { !codexReader.sessions.isEmpty }

    private enum ConnectionState {
        case none, claudeOnly, codexOnly, both
    }
    // 섹션 표시(레이아웃)는 설정 토글이 기준 — 데이터 유무와 무관하게 일단 보여준다.
    private var connectionState: ConnectionState {
        switch (limits.claudeEnabled, limits.codexEnabled) {
        case (false, false): return .none
        case (true,  false): return .claudeOnly
        case (false, true):  return .codexOnly
        case (true,  true):  return .both
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch connectionState {
            case .none:
                emptyStateView
            case .claudeOnly:
                claudeHeader
                Divider()
                claudeUsageRow
            case .codexOnly:
                codexHeader
                Divider()
                codexUsageRow
            case .both:
                claudeHeader
                Divider()
                claudeUsageRow
                Divider()
                codexHeader
                Divider()
                codexUsageRow
            }
            Divider()
            menuButtons
        }
        .frame(width: 240)
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Image(nsImage: AppDelegate.makeClaudeIcon())
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.tertiary)
                Image(nsImage: AppDelegate.makeCodexIcon())
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.tertiary)
            }
            Text("표시할 항목 없음")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("설정에서 Claude 또는 Codex를 켜세요")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
    }

    // MARK: - Claude section

    private var claudeHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text("Claude")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 3) {
                Circle()
                    .fill(isClaudeConnected ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                Text(isClaudeConnected ? "\(sessions.activeCount) 활성" : "대기 중")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(connectionState == .both ? Color.orange.opacity(0.05) : Color.clear)
    }

    private var claudeUsageRow: some View {
        let fiveResetDate = usageReader.usage?.fiveHourResetsAt
        let weekResetDate = usageReader.usage?.weeklyResetsAt
        let u = usageReader.usage
        let compact = connectionState == .both

        return HStack(spacing: 0) {
            tankBlock(
                label: "5시간 창",
                pct: appState.windowPercentRemaining,
                reset: u?.shortTimeUntilReset(fiveResetDate),
                resetMinutes: u?.minutesUntilReset(fiveResetDate),
                compact: compact
            )
            Divider()
            tankBlock(
                label: "이번 주",
                pct: appState.weeklyPercentRemaining,
                reset: u?.timeUntilReset(weekResetDate),
                resetMinutes: u?.minutesUntilReset(weekResetDate),
                compact: compact
            )
        }
        .padding(.vertical, compact ? 6 : 10)
    }

    private func tankBlock(label: String, pct: Double?, reset: String?,
                           resetMinutes: Double?, compact: Bool) -> some View {
        let tankH: CGFloat = compact ? 34 : 52
        let tankW: CGFloat = compact ? 24 : 32
        let numSize: CGFloat = compact ? 13 : 16

        return VStack(spacing: compact ? 2 : 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            if let pct {
                WaterTankView(pct: pct, color: pctColor(pct))
                    .frame(width: tankW, height: tankH)
                HStack(alignment: .center, spacing: 4) {
                    Text(String(format: "%.0f%%", pct * 100))
                        .font(.system(size: numSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(pctColor(pct))
                    if label == "5시간 창" {
                        UsageGauge(level: appState.tokenRateLevel)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: tankW, height: tankH)
                Text("--")
                    .font(.system(size: numSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 3) {
                Image(systemName: "arrow.clockwise").font(.system(size: 8))
                Text(reset ?? "--").font(.system(size: 9))
            }
            .foregroundStyle(resetColor(resetMinutes))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Codex section

    private var codexHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 10))
                .foregroundStyle(.blue)
            Text("Codex")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 3) {
                let todayCount = codexReader.sessions.filter {
                    Calendar.current.isDateInToday($0.startedAt)
                }.count
                Circle()
                    .fill(todayCount > 0 ? Color.blue : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                Text("\(todayCount) 오늘")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(connectionState == .both ? Color.blue.opacity(0.05) : Color.clear)
    }

    private var codexUsageRow: some View {
        let usedPct = codexReader.primaryUsedPercent / 100.0   // convert to 0–1
        let compact = connectionState == .both

        return HStack(spacing: 0) {
            // 5시간 quota bar (horizontal)
            VStack(spacing: compact ? 2 : 4) {
                Text("5시간 사용률")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 8)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(codexPctColor(usedPct))
                            .frame(width: geo.size.width * min(usedPct, 1.0), height: 8)
                            .animation(.easeInOut(duration: 0.5), value: usedPct)
                    }
                    .frame(height: 8)
                }
                .frame(height: 8)

                Text(String(format: "%.0f%% 사용", usedPct * 100))
                    .font(.system(size: compact ? 12 : 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(codexPctColor(usedPct))

                if let resetsAt = codexReader.primaryResetsAt {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 8))
                        Text(timeUntilLabel(resetsAt)).font(.system(size: 9))
                    }
                    .foregroundStyle(resetColor(resetsAt.timeIntervalSinceNow / 60))
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)

            Divider()

            // Today / weekly tokens
            VStack(spacing: compact ? 2 : 4) {
                Text("오늘 토큰")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Text(fmtTokens(codexReader.todayTokens))
                    .font(.system(size: compact ? 12 : 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.blue)
                Text("주간 \(fmtTokens(codexReader.weeklyTokens))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, compact ? 6 : 10)
    }

    // MARK: - Buttons

    private var menuButtons: some View {
        VStack(spacing: 0) {
            MenuItemRow(label: "대시보드 열기", icon: "chart.bar") { openDashboard() }
            Divider()
            MenuItemRow(label: "설정", icon: "gear") { openSettings() }
            Divider()
            MenuItemRow(label: "종료", icon: "power") { NSApplication.shared.terminate(nil) }

        }
    }

    // MARK: - Helpers

    private func pctColor(_ pct: Double) -> Color {
        switch pct {
        case 0.5...: return .green
        case 0.2..<0.5: return .orange
        default: return .red
        }
    }

    private func codexPctColor(_ usedPct: Double) -> Color {
        switch usedPct {
        case ..<0.5: return .blue
        case 0.5..<0.8: return .orange
        default: return .red
        }
    }

    private func resetColor(_ minutes: Double?) -> Color {
        guard let m = minutes else { return Color.secondary.opacity(0.3) }
        guard m > 0 else { return .red }
        if m > 60 { return .green }
        if m > 20 { return .orange }
        return .red
    }

    private func timeUntilLabel(_ date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        guard diff > 0 else { return "곧 갱신" }
        if diff < 3600 { return String(format: "%.0f분 후", diff / 60) }
        return String(format: "%.0f시간 후", diff / 3600)
    }

    private func fmtTokens(_ n: Int) -> String {
        switch n {
        case 0..<1_000: return "\(n)"
        case 1_000..<1_000_000: return String(format: "%.1fK", Double(n) / 1_000)
        default: return String(format: "%.1fM", Double(n) / 1_000_000)
        }
    }
}
