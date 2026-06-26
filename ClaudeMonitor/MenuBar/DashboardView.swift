// ClaudeMonitor/MenuBar/DashboardView.swift
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var profiles = ProfileStore.shared
    @State private var showAddProfile = false
    @State private var newProfileName = ""
    @State private var newProfilePath = ""

    var body: some View {
        HSplitView {
            // Left: profile list
            profileSidebar
                .frame(minWidth: 160, maxWidth: 200)

            // Right: usage data
            usageContent
        }
        .frame(width: 720, height: 520)
    }

    // MARK: - Profile sidebar

    private var profileSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("계정")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()

            List(profiles.profiles, selection: .constant(profiles.activeProfileId)) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name)
                            .font(.callout)
                        Text(p.claudeHomePath)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if p.id == profiles.activeProfileId {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { profiles.activate(p.id) }
                .contextMenu {
                    if profiles.profiles.count > 1 {
                        Button("삭제", role: .destructive) {
                            profiles.remove(id: p.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button {
                newProfileName = ""
                newProfilePath = URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent(".claude").path
                showAddProfile = true
            } label: {
                Label("계정 추가", systemImage: "plus")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .sheet(isPresented: $showAddProfile) {
            addProfileSheet
        }
    }

    private var addProfileSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("계정 추가")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("이름")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("예: 개인, 회사", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Claude 홈 디렉토리")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("~/.claude", text: $newProfilePath)
                        .textFieldStyle(.roundedBorder)
                    Button("찾기") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.begin { response in
                            if response == .OK, let url = panel.url {
                                newProfilePath = url.path
                            }
                        }
                    }
                }
                Text("Claude Code가 사용하는 설정 폴더 (보통 ~/.claude)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("취소") { showAddProfile = false }
                    .keyboardShortcut(.cancelAction)
                Button("추가") {
                    let path = newProfilePath.isEmpty
                        ? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude").path
                        : newProfilePath
                    profiles.add(name: newProfileName.isEmpty ? "새 계정" : newProfileName,
                                 claudeHomePath: path)
                    showAddProfile = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newProfileName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    // MARK: - Usage content

    private var usageContent: some View {
        VStack(spacing: 0) {
            // Summary header
            HStack(spacing: 32) {
                summaryCard(title: "5시간 창", tokens: appState.windowTokens,
                            pct: appState.windowPercentRemaining)
                summaryCard(title: "이번 주", tokens: appState.weekTokens,
                            pct: appState.weeklyPercentRemaining)
                summaryCard(title: "오늘 비용", tokens: nil,
                            cost: appState.todayCostUSD, pct: nil)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Daily table
            if appState.dailySummaries.isEmpty {
                Spacer()
                Text("데이터 없음 — Claude Code 사용 후 자동으로 채워집니다")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Table(appState.dailySummaries) {
                    TableColumn("날짜", value: \.date)
                    TableColumn("입력") { row in
                        Text(formatTokens(row.totalInputTokens)).monospacedDigit()
                    }
                    .width(80)
                    TableColumn("출력") { row in
                        Text(formatTokens(row.totalOutputTokens)).monospacedDigit()
                    }
                    .width(80)
                    TableColumn("합계") { row in
                        Text(formatTokens(row.totalInputTokens + row.totalOutputTokens))
                            .monospacedDigit().bold()
                    }
                    .width(90)
                    TableColumn("비용") { row in
                        Text(row.totalCostUSD.formatted(.currency(code: "USD"))).monospacedDigit()
                    }
                    .width(80)
                    TableColumn("세션") { row in
                        Text("\(row.sessionCount)").monospacedDigit()
                    }
                    .width(50)
                }
            }
        }
    }

    private func summaryCard(title: String, tokens: Int?, cost: Double? = nil, pct: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let pct {
                Text(String(format: "%.0f%%", pct * 100))
                    .font(.largeTitle.monospacedDigit().bold())
                    .foregroundStyle(pctColor(pct))
                if let t = tokens {
                    Text("사용: \(formatTokens(t))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let t = tokens {
                Text(formatTokens(t))
                    .font(.largeTitle.monospacedDigit().bold())
            } else if let c = cost {
                Text(c.formatted(.currency(code: "USD")))
                    .font(.largeTitle.monospacedDigit().bold())
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

    private func formatTokens(_ n: Int) -> String {
        switch n {
        case 0..<1_000: return "\(n)"
        case 1_000..<1_000_000: return String(format: "%.1fK", Double(n) / 1_000)
        default: return String(format: "%.1fM", Double(n) / 1_000_000)
        }
    }
}
