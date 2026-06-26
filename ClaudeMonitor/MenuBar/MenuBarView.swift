// ClaudeMonitor/MenuBar/MenuBarView.swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var usageReader = AnthropicUsageReader.shared
    @ObservedObject private var profiles = ProfileStore.shared
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact top row: account chip + source label
            HStack(spacing: 6) {
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
                    HStack(spacing: 3) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 10))
                        Text(profiles.activeProfile?.name ?? "기본")
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                if usageReader.usage != nil {
                    Text("Anthropic · \(usageReader.cacheAge)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("데이터 없음")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

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
        .frame(width: 250)
    }

    private func usageBlock(label: String, pctRemaining: Double?, resetLabel: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            if let pct = pctRemaining {
                Text(String(format: "%.0f%%", pct * 100))
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundStyle(pctColor(pct))

                Text("남음")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                ProgressView(value: pct)
                    .progressViewStyle(.linear)
                    .tint(pctColor(pct))
                    .frame(width: 88)
                    .scaleEffect(x: 1, y: 0.75)

                if let reset = resetLabel {
                    Text(reset)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("--")
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
