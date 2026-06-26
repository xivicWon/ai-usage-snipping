// ClaudeMonitor/MenuBar/MenuBarView.swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var usageReader = AnthropicUsageReader.shared
    @ObservedObject private var sessions = SessionReader.shared
    @ObservedObject private var settings = UsageLimits.shared
    @State private var editingEmail = false
    @State private var emailDraft = ""
    let openDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Account + session count row
            HStack(spacing: 8) {
                if editingEmail {
                    TextField("이메일 입력", text: $emailDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10))
                        .onSubmit {
                            settings.accountEmail = emailDraft
                            sessions.loadAccountPublic()
                            editingEmail = false
                        }
                    Button("저장") {
                        settings.accountEmail = emailDraft
                        sessions.loadAccountPublic()
                        editingEmail = false
                    }
                    .font(.system(size: 10))
                } else {
                    Button {
                        emailDraft = settings.accountEmail
                        editingEmail = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            if let acct = sessions.accountInfo {
                                Text(acct.username)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.primary)
                                if !acct.subscriptionType.isEmpty {
                                    Text(acct.displayPlan)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.purple.opacity(0.8))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    HStack(spacing: 3) {
                        Circle()
                            .fill(sessions.activeCount > 0 ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text("\(sessions.activeCount) 세션")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
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
