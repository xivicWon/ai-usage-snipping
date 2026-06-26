// ClaudeMonitor/MenuBar/MenuBarView.swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var usageReader = AnthropicUsageReader.shared
    @ObservedObject private var profiles = ProfileStore.shared
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profile picker
            profileHeader

            Divider()

            // Usage blocks
            HStack(spacing: 0) {
                usageBlock(
                    label: "5시간 창",
                    pctRemaining: appState.windowPercentRemaining,
                    resetLabel: usageReader.usage?.timeUntilReset(usageReader.usage?.fiveHourResetsAt)
                )
                Divider()
                usageBlock(
                    label: "이번 주",
                    pctRemaining: appState.weeklyPercentRemaining,
                    resetLabel: usageReader.usage?.timeUntilReset(usageReader.usage?.weeklyResetsAt)
                )
            }

            if let age = usageReader.usage.map({ _ in usageReader.cacheAge }) {
                Text("Anthropic 기준 · \(age) 업데이트")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            } else {
                Text("Anthropic 데이터 없음 — OMC 플러그인 필요")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            Divider()

            Button { openDashboard() } label: {
                Label("대시보드 열기", systemImage: "chart.bar")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Divider()

            Button { NSApplication.shared.terminate(nil) } label: {
                Text("종료").frame(maxWidth: .infinity, alignment: .leading)
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

    private func usageBlock(label: String, pctRemaining: Double?, resetLabel: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            if let pct = pctRemaining {
                Text(String(format: "%.0f%%", pct * 100))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(pctColor(pct))

                Text("남음")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ProgressView(value: pct)
                    .progressViewStyle(.linear)
                    .tint(pctColor(pct))
                    .frame(width: 100)
                    .scaleEffect(x: 1, y: 0.8)

                if let reset = resetLabel {
                    Text(reset)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("--")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pctColor(_ pct: Double) -> Color {
        switch pct {
        case 0.5...: return .green
        case 0.2..<0.5: return .orange
        default: return .red
        }
    }
}
