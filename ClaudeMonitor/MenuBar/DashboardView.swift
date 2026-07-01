// ClaudeMonitor/MenuBar/DashboardView.swift
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var sessions = SessionReader.shared
    @ObservedObject private var usageReader = AnthropicUsageReader.shared
    @ObservedObject private var codexReader = CodexSessionReader.shared

    @State private var selectedTool: AITool = .claude
    @ObservedObject private var router = DashboardRouter.shared

    enum AITool: String, CaseIterable {
        case claude = "Claude"
        case codex  = "Codex"
        case retro  = "🪞 회고"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tool picker header
            HStack {
                Picker("", selection: $selectedTool) {
                    ForEach(AITool.allCases, id: \.self) { tool in
                        Text(tool.rawValue).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            switch selectedTool {
            case .claude:
                HSplitView {
                    sessionSidebar.frame(minWidth: 180, maxWidth: 220)
                    usageContent
                }
            case .codex:
                HSplitView {
                    codexSidebar.frame(minWidth: 180, maxWidth: 220)
                    codexContent
                }
            case .retro:
                RetrospectiveView()
            }
        }
        .frame(width: 760, height: 520)
        .onReceive(router.$requestedTool.compactMap { $0 }) { raw in
            if let tool = AITool(rawValue: raw) { selectedTool = tool }
            router.requestedTool = nil
        }
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
            // Quota cards
            HStack(spacing: 28) {
                summaryCard(title: "5시간 창",
                            pct: appState.windowPercentRemaining,
                            reset: usageReader.usage?.timeUntilReset(usageReader.usage?.fiveHourResetsAt))
                summaryCard(title: "이번 주",
                            pct: appState.weeklyPercentRemaining,
                            reset: usageReader.usage?.timeUntilReset(usageReader.usage?.weeklyResetsAt))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Efficiency metrics
            HStack(spacing: 0) {
                efficiencyCard(
                    title: "컨텍스트 크기",
                    value: fmtTokens(appState.weeklyStats.avgContextSize),
                    hint: appState.weeklyStats.avgContextSize > 80_000 ? "컨텍스트 비대" : "정상",
                    color: appState.weeklyStats.avgContextSize <= 40_000 ? .green
                         : appState.weeklyStats.avgContextSize <= 80_000 ? .orange : .red
                )
                Divider().frame(height: 44)
                efficiencyCard(
                    title: "Opus 비율",
                    value: String(format: "%.0f%%", appState.weeklyStats.opusRatio * 100),
                    hint: appState.weeklyStats.opusRatio > 0.5 ? "Sonnet 전환 검토" : "효율적",
                    color: appState.weeklyStats.opusRatio <= 0.2 ? .green
                         : appState.weeklyStats.opusRatio <= 0.5 ? .orange : .red
                )
                Divider().frame(height: 44)
                efficiencyCard(
                    title: "호출당 토큰",
                    value: fmtTokens(appState.weeklyStats.avgTokensPerCall),
                    hint: appState.weeklyStats.avgTokensPerCall > 50_000 ? "입출력 비대" : "정상",
                    color: appState.weeklyStats.avgTokensPerCall <= 30_000 ? .green
                         : appState.weeklyStats.avgTokensPerCall <= 50_000 ? .orange : .red
                )
            }
            .padding(.vertical, 10)

            Divider()

            // Hourly heatmap
            hourlyHeatmap

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

    private func efficiencyCard(title: String, value: String, hint: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(hint)
                .font(.system(size: 9))
                .foregroundStyle(color.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hourly heatmap

    private var hourlyHeatmap: some View {
        // dayOfWeek: 0=Sun…6=Sat → reorder to Mon(1)…Sun(0)
        let dayOrder = [1, 2, 3, 4, 5, 6, 0]
        let dayLabels = ["월", "화", "수", "목", "금", "토", "일"]

        // Build lookup [dayOfWeek][hour] = tokens
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        for h in appState.weeklyHourly {
            let d = h.dayOfWeek < 7 ? h.dayOfWeek : 0
            let hr = h.hour < 24 ? h.hour : 0
            grid[d][hr] = h.tokens
        }
        let maxVal = grid.flatMap { $0 }.max() ?? 1

        return VStack(alignment: .leading, spacing: 6) {
            Text("시간대별 사용 패턴")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            HStack(alignment: .top, spacing: 4) {
                // Day labels
                VStack(alignment: .trailing, spacing: 1) {
                    Color.clear.frame(height: 10) // hour label spacer
                    ForEach(0..<7, id: \.self) { i in
                        Text(dayLabels[i])
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .frame(height: 10)
                    }
                }

                // Grid
                VStack(spacing: 1) {
                    // Hour labels (every 6h)
                    HStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { h in
                            Group {
                                if h % 6 == 0 {
                                    Text("\(h)")
                                        .font(.system(size: 7))
                                        .foregroundStyle(.tertiary)
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: 14, height: 10, alignment: .leading)
                        }
                    }

                    // Cells
                    ForEach(0..<7, id: \.self) { rowIdx in
                        let dow = dayOrder[rowIdx]
                        HStack(spacing: 1) {
                            ForEach(0..<24, id: \.self) { h in
                                let val = grid[dow][h]
                                let intensity = maxVal > 0 ? Double(val) / Double(maxVal) : 0
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(cellColor(intensity))
                                    .frame(width: 14, height: 10)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func cellColor(_ intensity: Double) -> Color {
        if intensity == 0 { return Color.secondary.opacity(0.08) }
        // blue → orange gradient by intensity
        return Color(hue: 0.6 - intensity * 0.37, saturation: 0.7, brightness: 0.85)
            .opacity(0.3 + intensity * 0.7)
    }

    // MARK: - Project chart

    private var weeklyProjectChart: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("최근 7일 프로젝트별 사용량")
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
        let avg = proj.avgTokensPerCall
        let avgColor: Color = avg <= 30_000 ? .secondary : avg <= 60_000 ? .orange : .red

        return HStack(spacing: 8) {
            Text(proj.projectName)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

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
                .frame(width: 46, alignment: .trailing)

            Text("avg \(fmtTokens(avg))")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(avgColor)
                .frame(width: 56, alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private func weekRangeLabel() -> String {
        let cal = Calendar.current
        let now = Date()
        guard let start = cal.date(byAdding: .day, value: -6, to: now) else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return "\(fmt.string(from: start)) – \(fmt.string(from: now))"
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

    // MARK: - Codex sidebar

    private var codexSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                statChip(value: "\(codexReader.sessions.filter { isToday($0.startedAt) }.count)",
                         label: "오늘", color: .blue)
                statChip(value: fmtTokens(codexReader.weeklyTokens), label: "주간", color: .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Divider()

            Text("세션")
                .font(.caption2).foregroundStyle(.tertiary).textCase(.uppercase)
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)

            List(codexReader.sessions) { session in
                codexSessionRow(session)
                    .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
            }
            .listStyle(.sidebar)

            Divider()

            Button { codexReader.reload() } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
                    .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private func codexSessionRow(_ s: CodexSession) -> some View {
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d HH:mm"
        return HStack(spacing: 6) {
            Circle()
                .fill(isToday(s.startedAt) ? Color.blue : Color.secondary.opacity(0.3))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.projectName)
                    .font(.caption.weight(isToday(s.startedAt) ? .semibold : .regular))
                    .lineLimit(1)
                Text(fmtTokens(s.totalTokens) + " · " + fmt.string(from: s.startedAt))
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Codex content

    private var codexContent: some View {
        VStack(spacing: 0) {
            // Quota card
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("5시간 사용률")
                        .font(.caption2).foregroundStyle(.tertiary).textCase(.uppercase)
                    let pct = codexReader.primaryUsedPercent / 100.0
                    Text(String(format: "%.0f%%", pct * 100))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(pct < 0.5 ? .green : pct < 0.8 ? .orange : .red)
                    if let resetsAt = codexReader.primaryResetsAt {
                        Text(timeUntilLabel(resetsAt))
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("오늘 토큰")
                        .font(.caption2).foregroundStyle(.tertiary).textCase(.uppercase)
                    Text(fmtTokens(codexReader.todayTokens))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text("주간: \(fmtTokens(codexReader.weeklyTokens))")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Project breakdown
            codexProjectChart
        }
    }

    private var codexProjectChart: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("최근 7일 프로젝트별 사용량")
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

            if codexReader.weeklyProjects.isEmpty {
                Spacer()
                Text("데이터 없음").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                let maxTok = codexReader.weeklyProjects.first?.totalTokens ?? 1
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(codexReader.weeklyProjects) { proj in
                            codexProjectBar(proj, maxTokens: maxTok)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func codexProjectBar(_ proj: CodexProjectSummary, maxTokens: Int) -> some View {
        let ratio = Double(proj.totalTokens) / Double(maxTokens)
        return HStack(spacing: 8) {
            Text(proj.projectName)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3).fill(Color.blue.opacity(0.65))
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 14)

            Text(fmtTokens(proj.totalTokens))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)

            Text("\(proj.sessionCount)세션")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func timeUntilLabel(_ date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        guard diff > 0 else { return "곧 갱신" }
        if diff < 3600 { return String(format: "%.0f분 후 갱신", diff / 60) }
        return String(format: "%.0f시간 후 갱신", diff / 3600)
    }
}
