// ClaudeMonitor/Data/ClaudeCodeHUDConnector.swift
import Foundation

/// 현재 사용량 연결이 어느 단계(tier)에 해당하는지 — 설정 UI 가 단계별 적용 버튼을
/// 보여주는 데 사용한다.
enum HUDLinkState: Equatable {
    case external                  // ① 외부 HUD(OMC 등)가 데이터를 제공 중 → 연결 불필요
    case empty                     // ② statusLine 비어있음 → 직접 등록 가능
    case foreign(command: String)  // ③ 다른 HUD 가 점유 중 → 체이닝으로 공존
    case registered                // 우리가 이미 연결됨
}

/// Registers ClaudeMonitor as a Claude Code statusLine HUD.
///
/// 등록처는 `~/.claude/settings.json` 이다. user 레벨 `settings.local.json` 의
/// statusLine 은 Claude Code 가 적용하지 않아(실측 확인) 우리 HUD 가 실행되지 않으므로,
/// 실제로 동작하는 settings.json 을 사용한다. 등록 시 기존 statusLine 을 저장해 두고,
/// 연결 해제 시 그대로 복원한다(비파괴적). 과거 버전이 settings.local.json 에 남긴
/// 우리 항목은 등록/해제 시 정리한다.
@MainActor
final class ClaudeCodeHUDConnector: ObservableObject {
    static let shared = ClaudeCodeHUDConnector()

    @Published private(set) var isRegistered = false
    @Published private(set) var lastReceivedAt: Date?
    @Published private(set) var linkState: HUDLinkState = .empty
    /// 우리 HUD 의 표시 스타일. 변경 시 ~/.claudemonitor/hud-style 에 즉시 기록되어
    /// 다음 렌더부터 반영된다(재등록 불필요).
    @Published var hudStyle: String = UserDefaults.standard.string(forKey: "hudStyle") ?? "full" {
        didSet {
            UserDefaults.standard.set(hudStyle, forKey: "hudStyle")
            try? writeStyleFile()
        }
    }

    /// 선택 가능한 스타일: (식별자, 한글 라벨)
    static let availableStyles: [(id: String, label: String)] = [
        ("full", "전체"),
        ("compact", "컴팩트"),
        ("minimal", "미니멀"),
        ("dev", "개발"),
        ("rate", "사용량만")
    ]

    private let monitorDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claudemonitor")
    private let hudScriptPath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claudemonitor/hud.sh")
    private let hudCachePath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claudemonitor/hud-cache.json")
    /// 우리 HUD 를 그려주는 node 렌더러 스크립트
    private let renderScriptPath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claudemonitor/hud-render.mjs")
    /// 렌더러가 읽는 스타일 선택 파일
    private let hudStylePath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claudemonitor/hud-style")
    /// 우리가 statusLine 을 기록하는 파일 (등록처) — 실제로 동작하는 위치
    private let settingsPath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/settings.json")
    /// 과거에 우리 항목을 잘못 써둔 위치 — 정리(제거) 용도로만 참조
    private let localSettingsPath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/settings.local.json")

    private let ourCommandMarker = ".claudemonitor/hud.sh"
    private var dirWatcher: DispatchSourceFileSystemObject?

    private init() {
        checkStatus()
        healIfRegistered()             // 운영중 self-heal: 망가진 항목이면 조용히 복구
        refreshScriptsIfRegistered()   // 앱 업데이트 시 최신 hud.sh/렌더러/스타일 반영
        startWatchingDir()
    }

    /// 등록된 상태라면 on-disk 스크립트를 현재 앱 버전으로 다시 쓴다(렌더러 갱신 등).
    private func refreshScriptsIfRegistered() {
        guard isRegistered else { return }
        try? writeHUDScript()
        try? writeRenderScript()
        try? writeStyleFile()
    }

    // MARK: - Registration

    func register() throws {
        try FileManager.default.createDirectory(at: monitorDir, withIntermediateDirectories: true)
        try writeHUDScript()
        try writeRenderScript()
        try? writeStyleFile()

        let current = statusLineDict(in: settingsPath)
        let currentCmd = current?["command"] as? String
        let alreadyOurs = currentCmd?.contains(ourCommandMarker) ?? false

        // 기존 statusLine(우리 것 아님)을 복원용으로 저장 — 우리 것이면 기존 백업 유지
        if !alreadyOurs {
            if let current,
               let data = try? JSONSerialization.data(withJSONObject: current),
               let saved = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(saved, forKey: "hudSavedStatusLine")
            } else {
                UserDefaults.standard.removeObject(forKey: "hudSavedStatusLine")
            }
        }

        try writeStatusLine(["type": "command", "command": wrapperCommand], to: settingsPath)
        removeStrayLocalEntry()   // 과거 settings.local.json 에 잘못 써둔 우리 항목 정리
        checkStatus()
    }

    func unregister() throws {
        // 저장해 둔 원래 statusLine 복원, 없으면 우리 것 제거
        if let saved = UserDefaults.standard.string(forKey: "hudSavedStatusLine"),
           let data = saved.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            try writeStatusLine(dict, to: settingsPath)
        } else if statusLineCommand(in: settingsPath)?.contains(ourCommandMarker) == true {
            try writeStatusLine(nil, to: settingsPath)
        }
        UserDefaults.standard.removeObject(forKey: "hudSavedStatusLine")
        removeStrayLocalEntry()
        checkStatus()
    }

    /// ① 최초설치 잠수함 패치: 앱 생애 최초 1회만 자동 등록한다.
    /// 외부 소스(OMC 등)가 이미 데이터를 제공 중이면 무간섭. 사용자가 의도적으로
    /// 등록 해제한 뒤에는 다시 밀어넣지 않도록 플래그로 가드한다.
    func autoRegisterOnFirstLaunch() {
        checkStatus()
        let key = "didAutoRegisterHUD"
        guard !UserDefaults.standard.bool(forKey: key) else {
            healIfRegistered()
            return
        }
        UserDefaults.standard.set(true, forKey: key)

        // 무위험인 '빈 슬롯'만 자동 연결한다. 외부 소스(①)·다른 HUD 공존(③)처럼
        // 기존 환경에 영향이 있는 단계는 사용자가 설정의 '사용량 연결' 버튼으로
        // 직접 단계 적용한다.
        switch linkState {
        case .registered:        healIfRegistered()
        case .empty:             try? register()
        case .external, .foreign: break
        }
    }

    /// local 의 내 statusLine 항목이 존재하지만 형식이 잘못된 경우(예: `type` 누락,
    /// 경로 변경)에만 올바른 값으로 다시 쓴다. 정상이면 아무 것도 하지 않는다(멱등).
    func healIfRegistered() {
        guard let statusLine = statusLineDict(in: settingsPath),
              let command = statusLine["command"] as? String,
              command.contains(ourCommandMarker) else { return }

        let healthy = (statusLine["type"] as? String) == "command"
            && command == wrapperCommand
        guard !healthy else { return }

        try? writeStatusLine(["type": "command", "command": wrapperCommand], to: settingsPath)
        checkStatus()
    }

    // MARK: - Status

    func checkStatus() {
        let cmd = statusLineCommand(in: settingsPath)
        isRegistered = cmd?.contains(ourCommandMarker) ?? false
        updateLastReceived()

        // 단계별 적용 버튼용 상태 판정
        if isRegistered {
            linkState = .registered
        } else if externalDataIsFresh() {
            linkState = .external
        } else if let effective = cmd, !effective.contains(ourCommandMarker) {
            linkState = .foreign(command: effective)
        } else {
            linkState = .empty
        }
    }

    /// 외부 HUD 캐시(고정 후보 + 탐색 발견 포함)가 최근 갱신되었는지 — Tier① 판단용.
    /// 탐색 로직은 리더에 일원화되어 있어 그대로 위임한다.
    func externalDataIsFresh() -> Bool {
        AnthropicUsageReader.shared.hasFreshExternalData()
    }

    // MARK: - Private

    private var wrapperCommand: String { "bash \(hudScriptPath.path)" }

    private func statusLineDict(in url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["statusLine"] as? [String: Any]
    }

    private func statusLineCommand(in url: URL) -> String? {
        statusLineDict(in: url)?["command"] as? String
    }

    private func startWatchingDir() {
        let fd = open(monitorDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: .global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.updateLastReceived()
                AnthropicUsageReader.shared.reload()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        dirWatcher = src
    }

    private func updateLastReceived() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: hudCachePath.path)
        lastReceivedAt = attrs?[.modificationDate] as? Date
    }

    /// hud.sh — stdin 을 캐시에 복사한 뒤, node 렌더러로 우리 HUD 한 줄을 출력한다.
    private func writeHUDScript() throws {
        let script = """
        #!/bin/bash
        # ClaudeMonitor HUD — receives session JSON from Claude Code CLI via stdin,
        # caches it for the menu-bar app, and renders our own status line.
        DIR="$HOME/.claudemonitor"
        mkdir -p "$DIR"
        INPUT="$(cat)"
        [ -n "${INPUT// /}" ] && printf '%s' "$INPUT" > "$DIR/hud-cache.json"
        printf '%s' "$INPUT" | node "$DIR/hud-render.mjs" 2>/dev/null
        """
        try script.write(to: hudScriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: hudScriptPath.path
        )
    }

    /// hud-render.mjs — statusLine JSON 을 파싱해 한 줄 HUD 를 ANSI 컬러로 출력한다.
    /// model · action · session · ctx · 5h · week · git branch · tool · agent · cost.
    /// (action/tool/agent 는 statusLine JSON 에 없어 transcript 꼬리에서 추출한다.)
    private func writeRenderScript() throws {
        let script = """
        import fs from 'fs';
        import { execSync } from 'child_process';

        let raw = '';
        try { raw = fs.readFileSync(0, 'utf8'); } catch { process.exit(0); }
        let d;
        try { d = JSON.parse(raw); } catch { process.exit(0); }

        const E = String.fromCharCode(27);
        const C = {
          r: E + '[0m', dim: E + '[2m', gray: E + '[90m',
          red: E + '[31m', grn: E + '[32m', yel: E + '[33m',
          blu: E + '[34m', mag: E + '[35m', cyn: E + '[36m', org: E + '[38;5;208m'
        };
        const lvl = (p) => (p >= 80 ? C.red : p >= 50 ? C.yel : C.grn);

        const DIR = (process.env.HOME || '') + '/.claudemonitor';
        let style = 'full';
        try { style = (fs.readFileSync(DIR + '/hud-style', 'utf8').trim()) || 'full'; } catch { }

        // 명명된 세그먼트를 만들어 두고, 스타일이 그중 일부를 골라 출력한다.
        const P = {};

        const ver = d.version || '';
        P.ver = C.cyn + '[CC#' + ver + ']' + C.r;

        const model = (d.model && (d.model.display_name || d.model.id)) || '';
        if (model) P.model = C.mag + '◆ ' + model + C.r;

        // transcript 꼬리에서 action / tool / agent 추출
        let action = '', tool = '', agent = '';
        try {
          const tp = d.transcript_path;
          if (tp && fs.existsSync(tp)) {
            const st = fs.statSync(tp);
            const len = Math.min(st.size, 65536);
            const fd = fs.openSync(tp, 'r');
            const buf = Buffer.alloc(len);
            fs.readSync(fd, buf, 0, len, st.size - len);
            fs.closeSync(fd);
            const lines = buf.toString('utf8').split(String.fromCharCode(10)).filter(Boolean);
            for (let i = lines.length - 1; i >= 0; i--) {
              let ev; try { ev = JSON.parse(lines[i]); } catch { continue; }
              const role = ev.type || (ev.message && ev.message.role) || '';
              const content = ev.message && ev.message.content;
              if (Array.isArray(content)) {
                for (let j = content.length - 1; j >= 0; j--) {
                  const it = content[j];
                  if (it && it.type === 'tool_use') {
                    if (!tool) tool = it.name || '';
                    if (it.name === 'Task' && !agent && it.input) agent = it.input.subagent_type || '';
                  }
                }
              }
              if (!action) {
                if (role.toLowerCase() === 'assistant') action = tool ? 'running' : 'replying';
                else if (role.toLowerCase() === 'user') action = 'thinking';
              }
              if (action && tool && agent) break;
            }
          }
        } catch { }
        if (action) P.action = C.gray + '▸ ' + action + C.r;

        const sid = (d.session_id || '').slice(0, 6);
        if (sid) P.sid = C.dim + '#' + sid + C.r;

        const cw = d.context_window;
        if (cw && typeof cw.used_percentage === 'number') {
          P.ctx = C.gray + 'ctx ' + C.r + lvl(cw.used_percentage) + Math.round(cw.used_percentage) + '%' + C.r;
        }

        const fmtReset = (ts) => {
          if (!ts) return '';
          const ms = ts * 1000 - Date.now();
          if (ms <= 0) return '';
          const m = Math.floor(ms / 60000);
          return m >= 60 ? (' ' + Math.floor(m / 60) + 'h') : (' ' + m + 'm');
        };
        const rate = (label, o) => {
          if (!o || typeof o.used_percentage !== 'number') return null;
          return C.gray + label + ' ' + C.r + lvl(o.used_percentage) + Math.round(o.used_percentage) + '%' + C.dim + fmtReset(o.resets_at) + C.r;
        };
        const rl = d.rate_limits || {};
        const r5 = rate('5h', rl.five_hour); if (r5) P['5h'] = r5;
        const rw = rate('wk', rl.seven_day); if (rw) P.wk = rw;

        let branch = '';
        try {
          const dir = (d.workspace && d.workspace.current_dir) || d.cwd || '.';
          branch = execSync('git -C "' + dir + '" rev-parse --abbrev-ref HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
        } catch { }
        if (branch) P.git = C.cyn + 'git:' + branch + C.r;

        if (tool) P.tool = C.blu + 'tool:' + tool + C.r;
        if (agent) P.agent = C.org + '@' + agent + C.r;

        if (d.cost && typeof d.cost.total_cost_usd === 'number') {
          P.cost = C.dim + '$' + d.cost.total_cost_usd.toFixed(2) + C.r;
        }

        const STYLES = {
          full:    ['ver', 'model', 'action', 'sid', 'ctx', '5h', 'wk', 'git', 'tool', 'agent', 'cost'],
          compact: ['model', 'ctx', '5h', 'wk', 'git'],
          minimal: ['model', '5h', 'wk'],
          dev:     ['model', 'ctx', 'git', 'tool', 'agent', 'cost'],
          rate:    ['5h', 'wk']
        };
        const order = STYLES[style] || STYLES.full;
        const seg = order.map((k) => P[k]).filter(Boolean);
        process.stdout.write(seg.join(C.gray + ' │ ' + C.r));
        """
        try script.write(to: renderScriptPath, atomically: true, encoding: .utf8)
    }

    /// 선택된 스타일을 ~/.claudemonitor/hud-style 에 기록한다. 렌더러가 매 렌더마다 읽는다.
    private func writeStyleFile() throws {
        try FileManager.default.createDirectory(at: monitorDir, withIntermediateDirectories: true)
        try hudStyle.write(to: hudStylePath, atomically: true, encoding: .utf8)
    }

    /// 주어진 설정 파일에 statusLine 을 병합 기록(nil 이면 키 제거). 다른 키는 보존.
    private func writeStatusLine(_ statusLine: [String: Any]?, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        if let statusLine {
            json["statusLine"] = statusLine
        } else {
            json.removeValue(forKey: "statusLine")
        }

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    /// 과거 버전이 ~/.claude/settings.local.json 에 잘못 써둔 우리 statusLine 을 제거한다
    /// (user-local 은 statusLine 에 적용되지 않아 무의미). '우리 것'일 때만 제거.
    private func removeStrayLocalEntry() {
        guard let command = statusLineCommand(in: localSettingsPath),
              command.contains(ourCommandMarker) else { return }
        try? writeStatusLine(nil, to: localSettingsPath)
    }
}
