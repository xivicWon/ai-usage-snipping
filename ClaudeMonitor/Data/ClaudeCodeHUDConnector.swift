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

/// Registers ClaudeMonitor as a Claude Code statusLine HUD — **적응형 3단** 전략으로
/// 기존 환경에 미치는 영향을 최소화한다.
///
///  ① 외부 HUD(OMC 등)가 이미 rate_limits 를 캐싱 중이면 → settings 를 전혀 건드리지
///     않는다. (읽기는 AnthropicUsageReader 가 그 캐시를 직접 본다.)
///  ② statusLine 슬롯이 비어 있으면 → settings.local.json 에 우리 항목만 추가.
///  ③ 다른 HUD 가 슬롯을 쓰고 있으면 → 그 명령을 보관해 두고, 우리 hud.sh 가 stdin 을
///     캐시에 복사한 뒤 **원래 명령으로 그대로 전달**한다(체이닝). 기존 HUD 는 계속
///     화면에 표시되고, 등록 해제 시 원래 상태로 복원된다.
///
/// 등록처는 항상 `~/.claude/settings.local.json` (local 이 user 설정보다 우선) 이며,
/// 사용자의 `settings.json` 은 우리가 과거에 남긴 흔적을 정리할 때만 손댄다.
@MainActor
final class ClaudeCodeHUDConnector: ObservableObject {
    static let shared = ClaudeCodeHUDConnector()

    @Published private(set) var isRegistered = false
    @Published private(set) var lastReceivedAt: Date?
    @Published private(set) var linkState: HUDLinkState = .empty

    private let monitorDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claudemonitor")
    private let hudScriptPath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claudemonitor/hud.sh")
    private let hudCachePath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claudemonitor/hud-cache.json")
    /// 우리 HUD 를 그려주는 node 렌더러 스크립트
    private let renderScriptPath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claudemonitor/hud-render.mjs")
    /// 우리가 statusLine 을 기록하는 파일 (등록처)
    private let localSettingsPath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/settings.local.json")
    /// 사용자 영역 — 읽기 + 과거에 우리가 남긴 흔적 정리 용도로만 사용
    private let settingsPath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/settings.json")

    private let ourCommandMarker = ".claudemonitor/hud.sh"
    private var dirWatcher: DispatchSourceFileSystemObject?

    private init() {
        checkStatus()
        healIfRegistered()        // 운영중 self-heal: 망가진 항목이면 조용히 복구
        startWatchingDir()
    }

    // MARK: - Registration

    func register() throws {
        try FileManager.default.createDirectory(at: monitorDir, withIntermediateDirectories: true)
        try writeHUDScript()
        try writeRenderScript()

        // 이미 우리 항목이 local 에 있으면 형식만 보정하고 종료(복원 정보 보존)
        if let command = statusLineCommand(in: localSettingsPath), command.contains(ourCommandMarker) {
            try updateLocalSettings(register: true)
            cleanupLegacyGlobalEntry()
            checkStatus()
            return
        }

        // 기존 statusLine(우리 것 아님)을 복원용으로 보관해 둔다 — 해제 시 되돌리기 위함
        let localCmd  = statusLineCommand(in: localSettingsPath)
        let globalCmd = statusLineCommand(in: settingsPath)
        let foreign = [localCmd, globalCmd]
            .compactMap { $0 }
            .first { !$0.contains(ourCommandMarker) }
        let foreignFromLocal = (localCmd.map { !$0.contains(ourCommandMarker) }) ?? false

        UserDefaults.standard.set(foreign ?? "", forKey: "hudChainCommand")
        UserDefaults.standard.set(foreignFromLocal, forKey: "hudChainFromLocal")

        try updateLocalSettings(register: true)   // 우리 HUD 를 local 에 기록
        cleanupLegacyGlobalEntry()
        checkStatus()
    }

    func unregister() throws {
        try updateLocalSettings(register: false)   // local 에서 우리 것 제거

        // 보관했던 기존 HUD 가 local 출신이면 복원 (global 출신은 자동 복귀)
        if UserDefaults.standard.bool(forKey: "hudChainFromLocal"),
           let command = UserDefaults.standard.string(forKey: "hudChainCommand"), !command.isEmpty {
            try restoreLocalStatusLine(command: command)
        }
        UserDefaults.standard.removeObject(forKey: "hudChainCommand")
        UserDefaults.standard.removeObject(forKey: "hudChainFromLocal")
        cleanupLegacyGlobalEntry()
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
        guard let statusLine = statusLineDict(in: localSettingsPath),
              let command = statusLine["command"] as? String,
              command.contains(ourCommandMarker) else { return }

        let healthy = (statusLine["type"] as? String) == "command"
            && command == wrapperCommand
        guard !healthy else { return }

        try? updateLocalSettings(register: true)
        checkStatus()
    }

    // MARK: - Status

    func checkStatus() {
        let localCmd = statusLineCommand(in: localSettingsPath)
        isRegistered = localCmd?.contains(ourCommandMarker) ?? false
        updateLastReceived()

        // 단계별 적용 버튼용 상태 판정
        if isRegistered {
            linkState = .registered
        } else if externalDataIsFresh() {
            linkState = .external
        } else if let effective = localCmd ?? statusLineCommand(in: settingsPath),
                  !effective.contains(ourCommandMarker) {
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
        const seg = [];

        const ver = d.version || '';
        seg.push(C.cyn + '[CC#' + ver + ']' + C.r);

        const model = (d.model && (d.model.display_name || d.model.id)) || '';
        if (model) seg.push(C.mag + '◆ ' + model + C.r);

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
        if (action) seg.push(C.gray + '▸ ' + action + C.r);

        const sid = (d.session_id || '').slice(0, 6);
        if (sid) seg.push(C.dim + '#' + sid + C.r);

        const cw = d.context_window;
        if (cw && typeof cw.used_percentage === 'number') {
          seg.push(C.gray + 'ctx ' + C.r + lvl(cw.used_percentage) + Math.round(cw.used_percentage) + '%' + C.r);
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
        const r5 = rate('5h', rl.five_hour); if (r5) seg.push(r5);
        const rw = rate('wk', rl.seven_day); if (rw) seg.push(rw);

        let branch = '';
        try {
          const dir = (d.workspace && d.workspace.current_dir) || d.cwd || '.';
          branch = execSync('git -C "' + dir + '" rev-parse --abbrev-ref HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
        } catch { }
        if (branch) seg.push(C.cyn + 'git:' + branch + C.r);

        if (tool) seg.push(C.blu + 'tool:' + tool + C.r);
        if (agent) seg.push(C.org + '@' + agent + C.r);

        if (d.cost && typeof d.cost.total_cost_usd === 'number') {
          seg.push(C.dim + '$' + d.cost.total_cost_usd.toFixed(2) + C.r);
        }

        process.stdout.write(seg.join(C.gray + ' │ ' + C.r));
        """
        try script.write(to: renderScriptPath, atomically: true, encoding: .utf8)
    }

    /// settings.local.json 에 statusLine 을 병합/제거한다. 기존 키(permissions, hooks 등)는 보존.
    private func updateLocalSettings(register: Bool) throws {
        try FileManager.default.createDirectory(
            at: localSettingsPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: localSettingsPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        if register {
            // Claude Code statusLine 스키마는 type 필수 — 누락 시 /doctor 가 오류로 표시
            json["statusLine"] = ["type": "command", "command": wrapperCommand]
        } else if let statusLine = json["statusLine"] as? [String: Any],
                  let command = statusLine["command"] as? String,
                  command.contains(ourCommandMarker) {
            // '내 것'일 때만 제거 — 사용자가 따로 지정한 statusLine 은 건드리지 않음
            json.removeValue(forKey: "statusLine")
        }

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: localSettingsPath, options: .atomic)
    }

    private func restoreLocalStatusLine(command: String) throws {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: localSettingsPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }
        json["statusLine"] = ["type": "command", "command": command]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: localSettingsPath, options: .atomic)
    }

    /// 과거 버전이 ~/.claude/settings.json 에 직접 써둔 우리 statusLine 을 제거한다.
    /// 이제 등록처는 settings.local.json 이므로 사용자 영역엔 흔적을 남기지 않는다.
    /// '우리 것'(`.claudemonitor/hud.sh`)일 때만 제거 — 사용자가 직접 만든 statusLine 은 그대로 둔다.
    private func cleanupLegacyGlobalEntry() {
        guard let data = try? Data(contentsOf: settingsPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusLine = json["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String,
              command.contains(ourCommandMarker) else { return }

        json.removeValue(forKey: "statusLine")
        guard let out = try? JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? out.write(to: settingsPath, options: .atomic)
    }
}
