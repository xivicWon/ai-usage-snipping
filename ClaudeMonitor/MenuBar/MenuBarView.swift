// ClaudeMonitor/MenuBar/MenuBarView.swift
import SwiftUI

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
    @ObservedObject private var sessions = SessionReader.shared
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            planRow
            Divider()
            usageRow
            Divider()
            menuButtons
        }
        .frame(width: 240)
    }

    // MARK: - Plan row

    private var planRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("Claude")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 3) {
                Circle()
                    .fill(sessions.activeCount > 0 ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                Text("\(sessions.activeCount)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Usage row (two tanks side by side)

    private var usageRow: some View {
        let fiveResetDate  = usageReader.usage?.fiveHourResetsAt
        let weekResetDate  = usageReader.usage?.weeklyResetsAt
        let u = usageReader.usage
        return HStack(spacing: 0) {
            tankBlock(
                label: "5시간 창",
                pct: appState.windowPercentRemaining,
                reset: u?.shortTimeUntilReset(fiveResetDate),
                resetMinutes: u?.minutesUntilReset(fiveResetDate)
            )
            Divider()
            tankBlock(
                label: "이번 주",
                pct: appState.weeklyPercentRemaining,
                reset: u?.timeUntilReset(weekResetDate),
                resetMinutes: u?.minutesUntilReset(weekResetDate)
            )
        }
        .padding(.vertical, 10)
    }

    private func tankBlock(label: String, pct: Double?, reset: String?, resetMinutes: Double?) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            if let pct {
                WaterTankView(pct: pct, color: pctColor(pct))
                    .frame(width: 32, height: 52)
                Text(String(format: "%.0f%%", pct * 100))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(pctColor(pct))
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 32, height: 52)
                Text("--")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
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

    private func resetColor(_ minutes: Double?) -> Color {
        guard let m = minutes else { return Color.secondary.opacity(0.3) }
        guard m > 0 else { return .red }
        if m > 60 { return .green }
        if m > 20 { return .orange }
        return .red
    }

    private func pctColor(_ pct: Double) -> Color {
        switch pct {
        case 0.5...: return .green
        case 0.2..<0.5: return .orange
        default: return .red
        }
    }

    // MARK: - Buttons

    private var menuButtons: some View {
        VStack(spacing: 0) {
            Button { openDashboard() } label: {
                Label("대시보드 열기", systemImage: "chart.bar")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 7)

            Divider()

            Button { openSettings() } label: {
                Label("설정", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 7)

            Divider()

            Button { NSApplication.shared.terminate(nil) } label: {
                Text("종료").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 7)
        }
    }

    private func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
