// ClaudeMonitor/MenuBar/MenuBarView.swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var profiles = ProfileStore.shared
    @ObservedObject private var limits = UsageLimits.shared
    @State private var showSettings = false
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profile picker
            profileHeader

            Divider()

            // Usage blocks
            HStack(spacing: 12) {
                usageBlock(
                    label: "5시간 창",
                    tokens: appState.windowTokens,
                    pctRemaining: appState.windowPercentRemaining
                )
                Divider().frame(height: 52)
                usageBlock(
                    label: "이번 주",
                    tokens: appState.weekTokens,
                    pctRemaining: appState.weeklyPercentRemaining
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if showSettings {
                Divider()
                settingsPanel
            }

            Divider()

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showSettings.toggle() }
            } label: {
                Label(showSettings ? "설정 닫기" : "한도 설정", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Button {
                openDashboard()
            } label: {
                Label("대시보드 열기", systemImage: "chart.bar")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("종료")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .frame(width: 260)
    }

    // MARK: - Profile header

    private var profileHeader: some View {
        Menu {
            ForEach(profiles.profiles) { p in
                Button {
                    profiles.activate(p.id)
                } label: {
                    HStack {
                        Text(p.name)
                        if p.id == profiles.activeProfileId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.circle")
                Text(profiles.activeProfile?.name ?? "계정")
                    .font(.caption.bold())
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Usage block

    private func usageBlock(label: String, tokens: Int, pctRemaining: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            if let pct = pctRemaining {
                Text(String(format: "%.0f%%", pct * 100))
                    .font(.title2.monospacedDigit().bold())
                    .foregroundStyle(pctColor(pct))
                Text("남음")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ProgressView(value: pct)
                    .progressViewStyle(.linear)
                    .tint(pctColor(pct))
                    .frame(width: 90)
                    .scaleEffect(x: 1, y: 0.7)
            } else {
                Text(formatTokens(tokens))
                    .font(.title3.monospacedDigit().bold())
                Text("← 한도 설정 필요")
                    .font(.caption2)
                    .foregroundStyle(.blue.opacity(0.8))
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

    // MARK: - Settings panel

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("토큰 한도 (0 = 미사용)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            limitField(label: "5시간 창", value: $limits.windowLimitTokens)
            limitField(label: "주간 한도", value: $limits.weeklyLimitTokens)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func limitField(label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 70, alignment: .leading)
            TextField("토큰 수", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospacedDigit())
                .frame(width: 110)
        }
    }

    private func formatTokens(_ n: Int) -> String {
        switch n {
        case 0..<1_000: return "\(n)"
        case 1_000..<1_000_000: return String(format: "%.1fK", Double(n) / 1_000)
        default: return String(format: "%.1fM", Double(n) / 1_000_000)
        }
    }
}
