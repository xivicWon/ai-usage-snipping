// ClaudeMonitor/MenuBar/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var limits = UsageLimits.shared
    @State private var autoCalcMessage: String?
    @State private var isCalculating = false

    var body: some View {
        TabView {
            claudeTab
                .tabItem { Label("Claude", systemImage: "sparkle") }
            codexTab
                .tabItem { Label("Codex", systemImage: "terminal") }
        }
        .frame(width: 480, height: 520)
        .padding()
    }

    // MARK: - Claude tab

    private var claudeTab: some View {
        Form {
            Section("사용") {
                Toggle("Claude 모니터링 사용", isOn: $limits.claudeEnabled)
            }

            rateThresholdSection

            // Claude Code HUD 연결 — 이전 '연결' 탭을 Claude 탭으로 통합
            HUDConnectionSections()
        }
        .formStyle(.grouped)
    }

    // MARK: - 처리율 게이지 임계값

    private var rateThresholdSection: some View {
        Section {
            rateRow(title: "기본 (1단계)", color: .green,   value: $limits.rateLevel1Min)
            rateRow(title: "많음 (2단계)", color: .orange,  value: $limits.rateLevel2Min)
            rateRow(title: "폭발적 (3단계)", color: .red,   value: $limits.rateLevel3Min)

            HStack {
                Button {
                    autoCalculateThresholds()
                } label: {
                    if isCalculating {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("자동 계산 (최근 30일)", systemImage: "wand.and.stars")
                    }
                }
                .disabled(isCalculating)

                Spacer()

                Button("기본값으로 복원") {
                    limits.resetRateThresholds()
                    autoCalcMessage = nil
                }
            }

            if let msg = autoCalcMessage {
                Text(msg).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("토큰 처리율 게이지")
        } footer: {
            Text("분당 input+output 토큰이 각 값 이상이면 해당 단계로 점등됩니다. '자동 계산'은 최근 30일 사용 분포의 p20·중앙값·p90으로 값을 산출합니다.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    /// 최근 30일 사용량 분포에서 임계값을 자동 산출해 적용한다. (활성 프로필 DB 직접 조회)
    private func autoCalculateThresholds() {
        isCalculating = true
        autoCalcMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let profileId = ProfileStore.shared.activeProfile?.id
            let result = (try? SQLiteStore(profileId: profileId))
                .flatMap { try? $0.suggestedRateThresholds(days: 30) }
            DispatchQueue.main.async {
                isCalculating = false
                if let t = result {
                    limits.rateLevel1Min = t.level1
                    limits.rateLevel2Min = t.level2
                    limits.rateLevel3Min = t.level3
                    autoCalcMessage = "산출 완료 — \(t.level1) / \(t.level2) / \(t.level3) 토큰/분으로 적용했습니다."
                } else {
                    autoCalcMessage = "데이터가 부족해 산출할 수 없습니다 (최근 30일 활동 분 20개 미만)."
                }
            }
        }
    }

    private func rateRow(title: String, color: Color, value: Binding<Int>) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
            Spacer()
            TextField("", value: value, formatter: Self.tokenFormatter)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .textFieldStyle(.roundedBorder)
            Text("토큰/분").foregroundStyle(.secondary).font(.caption)
        }
    }

    private static let tokenFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimum = 0
        f.maximum = 10_000_000
        f.allowsFloats = false
        return f
    }()

    // MARK: - Codex tab

    private var codexTab: some View {
        Form {
            Section("사용") {
                Toggle("Codex 모니터링 사용", isOn: $limits.codexEnabled)
            }

            Section {
                HStack {
                    TextField("~/.codex", text: $limits.codexHomePath)
                        .onChange(of: limits.codexHomePath) { _ in
                            CodexSessionReader.shared.reload()
                        }
                    Button("초기화") {
                        limits.codexHomePath = ""
                        CodexSessionReader.shared.reload()
                    }
                }
            } header: {
                Text("Codex 홈 경로")
            } footer: {
                Text("비워두면 기본값 ~/.codex 를 사용합니다.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Button("데이터 새로고침") {
                    CodexSessionReader.shared.reload()
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 큰 카드형 액션 버튼

private struct HUDActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    var disabled: Bool = false
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(hover ? tint.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(hover ? tint.opacity(0.55) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { hover = $0 }
        .animation(.easeInOut(duration: 0.1), value: hover)
    }
}

// MARK: - HUD Connection Sections (embedded inside the Claude tab's Form)

private struct HUDConnectionSections: View {
    @ObservedObject private var connector = ClaudeCodeHUDConnector.shared
    @ObservedObject private var reader    = AnthropicUsageReader.shared
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var isAnalyzing = false
    @State private var didCopyGuide = false

    /// 사용량이 안 잡힐 때 Claude Code 에 그대로 붙여넣어 요청할 수 있는 문구
    private let guidePrompt = """
    내 Claude Code statusLine 을 'bash ~/.claudemonitor/hud.sh' 로 설정해줘. \
    기존 statusLine 이 이미 있으면 덮어쓰지 말고, 그 출력도 그대로 유지되도록 \
    내 hud.sh 가 stdin 을 받아서 기존 명령으로 전달(체이닝)하게 구성해줘. \
    설정은 ~/.claude/settings.json 또는 settings.local.json 에 반영하면 돼.
    """

    var body: some View {
        Group {
            Section {
                HStack {
                    Circle()
                        .fill(reader.isConnected ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text(reader.isConnected ? "연결됨" : "연결 없음")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if let lastAt = connector.lastReceivedAt {
                        Text(relativeTime(lastAt))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if reader.isConnected {
                    HStack {
                        Text("캐시 나이")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(reader.cacheAge)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    if let src = reader.sourcePath {
                        HStack(alignment: .top) {
                            Text("출처")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(src)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }
                }
            } header: {
                Text("Claude Code HUD 상태")
            }

            Section {
                // 현재 감지된 단계 표시
                HStack(spacing: 8) {
                    Image(systemName: tierIcon)
                        .foregroundStyle(tierColor)
                    Text(tierTitle)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(tierBadge)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(tierColor.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(tierColor)
                }

                if connector.isRegistered {
                    // 표시 옵션 — 독립 축 (다음 렌더에 즉시 반영)
                    Picker("아이콘", selection: $connector.hudEmoji) {
                        Text("이모지").tag(true)
                        Text("플레인").tag(false)
                    }.pickerStyle(.segmented)
                    Picker("배경", selection: $connector.hudFilled) {
                        Text("채움").tag(true)
                        Text("비움").tag(false)
                    }.pickerStyle(.segmented)
                    // 레이아웃 — 드래그 앤 드롭으로 행 배치
                    Text("레이아웃")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HudLayoutEditor(connector: connector)

                    Button(role: .destructive) {
                        do { try connector.unregister(); reader.reload(); errorMessage = nil; statusMessage = nil }
                        catch { errorMessage = error.localizedDescription }
                    } label: {
                        Label("연결 해제", systemImage: "minus.circle")
                    }
                } else {
                    // 미연결 — 연결 액션(자동 분석 / 고급 HUD 설치)
                    connectActions
                }

                if let msg = statusMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
                if let err = errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("사용량 연결")
            } footer: {
                Text(tierFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 사용량이 안 잡힐 때 — Claude 로 직접 설정하는 가이드
            if !reader.isConnected {
                Section {
                    Text("사용량 데이터는 Claude Code의 statusLine 으로만 들어옵니다. 위 버튼으로 연결해도 표시되지 않으면, Claude Code 세션에서 직접 설정하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label("Claude Code에서 `/statusline` 실행 후 명령을 `bash ~/.claudemonitor/hud.sh` 로 지정",
                          systemImage: "1.circle")
                        .font(.caption)

                    Label("또는 Claude 에게 아래 문구로 요청 (기존 HUD 가 있으면 체이닝까지 부탁)",
                          systemImage: "2.circle")
                        .font(.caption)

                    Text(guidePrompt)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(guidePrompt, forType: .string)
                        didCopyGuide = true
                    } label: {
                        Label(didCopyGuide ? "복사됨" : "요청 문구 복사",
                              systemImage: didCopyGuide ? "checkmark" : "doc.on.doc")
                    }

                    Text("설정 후 아무 폴더에서 Claude Code 를 한 번 실행하면 사용량이 수신됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("사용량이 표시되지 않나요?")
                }
            }

            Section("동작 방식") {
                infoRow(step: "1", text: "이 앱을 Claude Code HUD로 등록")
                infoRow(step: "2", text: "Claude Code 실행 시 rate_limits JSON 수신")
                infoRow(step: "3", text: "~/.claudemonitor/hud-cache.json 에 캐시")
                infoRow(step: "4", text: "앱이 파일 변경 감지 → 즉시 UI 갱신")
            }
        }
        .onAppear { connector.checkStatus() }
    }

    // 위계: 자동 분석(기본·권장) 위, HUD 직접 설치(고급) 아래
    @ViewBuilder private var connectActions: some View {
        // 기본 — 자동 분석 (큰 1차, 권장)
        HUDActionCard(
            icon: "magnifyingglass",
            title: isAnalyzing ? "분석 중…" : "자동 분석",
            subtitle: "기존 사용량 데이터 탐색 · 무간섭 연결",
            tint: .green,
            disabled: isAnalyzing
        ) { runAutoAnalyze() }
        .padding(.vertical, 2)

        Text("이미 사용량 데이터를 제공하는 HUD를 찾아, 설정을 바꾸지 않고 그대로 읽습니다.")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider().padding(.vertical, 2)

        // 고급 — ClaudeMonitor HUD 직접 설치 (작은 2차)
        Text("고급 — ClaudeMonitor HUD 직접 설치")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
        Text("statusLine(settings.json)에 등록합니다. 기존 HUD가 있으면 저장 후 교체하며, 연결 해제 시 복원됩니다.")
            .font(.caption)
            .foregroundStyle(.secondary)
        Button { runRegister() } label: {
            Label("HUD 설정 및 연결", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 12))
        }
        .controlSize(.small)
    }

    private func runAutoAnalyze() {
        isAnalyzing = true
        errorMessage = nil
        statusMessage = "rate_limit 정보 탐색 중…"
        reader.rediscover { found, path in
            isAnalyzing = false
            connector.checkStatus()
            if found {
                statusMessage = "연결됨 (설정 변경 없음)\n출처: \(path ?? "—")"
            } else {
                statusMessage = "사용량 데이터를 찾지 못했습니다. ‘HUD 변경 및 연결’로 직접 등록하세요."
            }
        }
    }

    private func runRegister() {
        do {
            try connector.register()
            reader.reload()   // 출처/연결 상태 즉시 갱신
            errorMessage = nil
            statusMessage = "ClaudeMonitor HUD로 연결했습니다. (다음 statusLine 렌더부터 우리 HUD 표시·수신)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 단계별 상태 표현

    private var tierBadge: String {
        switch connector.linkState {
        case .external:   return "①"
        case .empty:      return "②"
        case .foreign:    return "③"
        case .registered: return "연결됨"
        }
    }

    private var tierTitle: String {
        switch connector.linkState {
        case .external:   return "외부 HUD 사용 중"
        case .empty:      return "연결 안 됨 (빈 슬롯)"
        case .foreign:    return "다른 HUD 감지됨"
        case .registered: return "ClaudeMonitor 연결됨"
        }
    }

    private var tierIcon: String {
        switch connector.linkState {
        case .external:   return "antenna.radiowaves.left.and.right"
        case .empty:      return "circle.dashed"
        case .foreign:    return "arrow.triangle.merge"
        case .registered: return "checkmark.circle.fill"
        }
    }

    private var tierColor: Color {
        switch connector.linkState {
        case .external:   return .green
        case .empty:      return .secondary
        case .foreign:    return .orange
        case .registered: return .accentColor
        }
    }

    private var tierFooter: String {
        switch connector.linkState {
        case .external:
            return "이미 외부 HUD가 사용량 데이터를 제공하고 있어 연결이 필요 없습니다. 그 캐시를 그대로 읽습니다(무간섭)."
        case .empty:
            return "statusLine이 비어 있습니다. 연결하면 ~/.claude/settings.json에 등록해 사용량을 직접 수신합니다."
        case .foreign(let command):
            return "기존 statusLine 감지: \(command)\n‘자동 분석 및 연결’은 이 HUD를 그대로 두고 데이터만 읽습니다. ‘HUD 변경 및 연결’은 ClaudeMonitor HUD로 교체하며, 해제 시 원래대로 복원됩니다."
        case .registered:
            return "~/.claude/settings.json에 연결됨(기존 statusLine은 저장·해제 시 복원). Claude Code 실행 시 쿼터 % 와 리셋 시각을 직접 수신합니다."
        }
    }

    private func infoRow(step: String, text: String) -> some View {
        HStack(spacing: 10) {
            Text(step)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(width: 18, height: 18)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60    { return "\(diff)초 전" }
        if diff < 3600  { return "\(diff/60)분 전" }
        return "\(diff/3600)시간 전"
    }
}

// MARK: - HUD 레이아웃 에디터 (드래그 앤 드롭)

private struct HudLayoutEditor: View {
    @ObservedObject var connector: ClaudeCodeHUDConnector

    private var activeRowIndices: [Int] {
        var seen = Set<Int>()
        for f in ClaudeCodeHUDConnector.availableFields where connector.hudFields.contains(f.id) {
            let r = connector.hudFieldRows[f.id]
                ?? ClaudeCodeHUDConnector.defaultFieldRows[f.id]
                ?? 0
            seen.insert(r)
        }
        return seen.sorted()
    }

    private func fields(inRow row: Int) -> [(id: String, label: String)] {
        ClaudeCodeHUDConnector.availableFields.filter {
            connector.hudFields.contains($0.id) &&
            (connector.hudFieldRows[$0.id] ?? ClaudeCodeHUDConnector.defaultFieldRows[$0.id] ?? 0) == row
        }
    }

    private var inactiveFields: [(id: String, label: String)] {
        ClaudeCodeHUDConnector.availableFields.filter { !connector.hudFields.contains($0.id) }
    }

    private var nextRowIndex: Int { (activeRowIndices.max() ?? -1) + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(activeRowIndices, id: \.self) { row in
                HudRowZone(rowIndex: row, fields: fields(inRow: row),
                           isNewRow: false, connector: connector)
            }
            HudRowZone(rowIndex: nextRowIndex, fields: [],
                       isNewRow: true, connector: connector)

            Divider().padding(.vertical, 2)

            HudInactiveZone(fields: inactiveFields, connector: connector)
        }
    }
}

// MARK: - 행 드롭 존

private struct HudRowZone: View {
    let rowIndex: Int
    let fields: [(id: String, label: String)]
    let isNewRow: Bool
    @ObservedObject var connector: ClaudeCodeHUDConnector
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isNewRow {
                    Text("행\(rowIndex)")
                        .foregroundStyle(Color.secondary.opacity(0.35))
                } else {
                    // 행 레이블 자체를 드래그 → 행 순서 변경
                    HStack(spacing: 2) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                        Text("행\(rowIndex)")
                            .foregroundStyle(.secondary)
                    }
                    .onDrag {
                        NSItemProvider(object: "row:\(rowIndex)" as NSString)
                    }
                    .help("드래그해서 행 순서 변경")
                }
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .frame(width: 38, alignment: .trailing)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isTargeted
                          ? Color.accentColor.opacity(0.10)
                          : Color.secondary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(
                                isTargeted ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.18),
                                style: StrokeStyle(lineWidth: 1,
                                                   dash: isNewRow ? [5, 3] : [])
                            )
                    )

                if fields.isEmpty {
                    Text(isNewRow ? "여기로 드래그하면 새 행이 됩니다" : "비어 있음 — 드래그해서 채우세요")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                } else {
                    HStack(spacing: 4) {
                        ForEach(fields, id: \.id) { f in
                            HudFieldChip(fieldId: f.id, label: f.label, connector: connector)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .onDrop(of: ["public.plain-text"], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let str = obj as? String, !str.isEmpty else { return }
                    DispatchQueue.main.async {
                        if str.hasPrefix("row:"), let srcRow = Int(str.dropFirst(4)) {
                            // 행 순서 교환 (새 행 존으로는 무시)
                            if !isNewRow { connector.swapRows(srcRow, rowIndex) }
                        } else {
                            // 항목 이동
                            connector.hudFields.insert(str)
                            connector.hudFieldRows[str] = rowIndex
                        }
                    }
                }
                return true
            }
        }
    }
}

// MARK: - 비활성 드롭 존

private struct HudInactiveZone: View {
    let fields: [(id: String, label: String)]
    @ObservedObject var connector: ClaudeCodeHUDConnector
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("비활성 — 드래그해서 행에 추가")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isTargeted
                          ? Color.secondary.opacity(0.12)
                          : Color.secondary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                    )

                if fields.isEmpty {
                    Text("모든 항목이 활성화됨")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                } else {
                    HudChipFlow(fields: fields, connector: connector)
                        .padding(6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .onDrop(of: ["public.plain-text"], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let str = obj as? String, !str.hasPrefix("row:") else { return }
                    DispatchQueue.main.async {
                        connector.hudFields.remove(str)
                    }
                }
                return true
            }
        }
    }
}

// MARK: - 칩 플로우 (줄바꿈 지원)

private struct HudChipFlow: View {
    let fields: [(id: String, label: String)]
    @ObservedObject var connector: ClaudeCodeHUDConnector

    var body: some View {
        // LazyVGrid로 자동 줄바꿈 처리
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 72, maximum: 140), spacing: 4)],
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(fields, id: \.id) { f in
                HudFieldChip(fieldId: f.id, label: f.label, connector: connector)
            }
        }
    }
}

// MARK: - 드래그 가능한 항목 칩

private struct HudFieldChip: View {
    let fieldId: String
    let label: String
    @ObservedObject var connector: ClaudeCodeHUDConnector

    private var currentColor: String {
        connector.hudFieldColors[fieldId] ?? "auto"
    }

    var body: some View {
        ZStack {
            // ① 시각 레이어 — 색상·텍스트·화살표를 직접 렌더
            HStack(spacing: 5) {
                Circle()
                    .fill(swatchColor(currentColor))
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            // ② 인터랙션 레이어 — 투명 Menu가 칩 전체를 덮음
            Menu {
                ForEach(ClaudeCodeHUDConnector.colorOptions, id: \.id) { c in
                    Button {
                        if c.id == "auto" {
                            connector.hudFieldColors[fieldId] = nil
                        } else {
                            connector.hudFieldColors[fieldId] = c.id
                        }
                    } label: {
                        Label(c.label,
                              systemImage: currentColor == c.id ? "checkmark" : "circle.fill")
                    }
                }
            } label: {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 5).fill(chipBgColor))
        .overlay(
            RoundedRectangle(cornerRadius: 5).strokeBorder(chipBorderColor, lineWidth: 1)
        )
        .onDrag {
            NSItemProvider(object: fieldId as NSString)
        }
    }

    private var chipBgColor: Color {
        let name = currentColor
        if name == "auto" {
            return connector.hudFields.contains(fieldId)
                ? Color.accentColor.opacity(0.11)
                : Color.secondary.opacity(0.09)
        }
        return swatchColor(name).opacity(0.18)
    }

    private var chipBorderColor: Color {
        let name = currentColor
        if name == "auto" {
            return connector.hudFields.contains(fieldId)
                ? Color.accentColor.opacity(0.28)
                : Color.secondary.opacity(0.18)
        }
        return swatchColor(name).opacity(0.55)
    }

    private func swatchColor(_ name: String) -> Color {
        switch name {
        case "blue":    return .blue
        case "purple":  return .purple
        case "green":   return .green
        case "yellow":  return .yellow
        case "cyan":    return .cyan
        case "orange":  return .orange
        case "red":     return .red
        case "gray":    return .gray
        default:        return Color.secondary.opacity(0.4)
        }
    }
}
