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
    // HUD 표시 옵션 — 독립 축. 변경 시 hud-opts.json 에 즉시 기록(다음 렌더 반영).
    @Published var hudEmoji: Bool = UserDefaults.standard.object(forKey: "hudEmoji") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hudEmoji, forKey: "hudEmoji"); try? writeOptsFile() }
    }
    @Published var hudFilled: Bool = UserDefaults.standard.object(forKey: "hudFilled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hudFilled, forKey: "hudFilled"); try? writeOptsFile() }
    }
    /// 표시할 항목들
    @Published var hudFields: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "hudFields") ?? ClaudeCodeHUDConnector.defaultFields) {
        didSet { UserDefaults.standard.set(Array(hudFields), forKey: "hudFields"); try? writeOptsFile() }
    }
    /// 항목별 행 번호 (멀티라인 모드). 미설정 항목은 defaultFieldRows 로 폴백.
    @Published var hudFieldRows: [String: Int] = {
        guard let data = UserDefaults.standard.data(forKey: "hudFieldRows"),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return ClaudeCodeHUDConnector.defaultFieldRows
        }
        return decoded
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(hudFieldRows) {
                UserDefaults.standard.set(data, forKey: "hudFieldRows")
            }
            try? writeOptsFile()
        }
    }
    /// 항목별 색상 이름. 미설정(nil)이면 기본 색상 사용.
    @Published var hudFieldColors: [String: String] = {
        guard let data = UserDefaults.standard.data(forKey: "hudFieldColors"),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(hudFieldColors) {
                UserDefaults.standard.set(data, forKey: "hudFieldColors")
            }
            try? writeOptsFile()
        }
    }

    static let defaultFields = ["ver", "model", "action", "sid", "dir", "ctx", "5h", "wk", "git", "tool", "agent", "cost"]
    /// 체크박스로 선택 가능한 표시 항목: (식별자, 한글 라벨) — 표시 순서
    static let availableFields: [(id: String, label: String)] = [
        ("ver", "CC 버전"), ("model", "모델"), ("action", "상태"), ("sid", "세션"),
        ("dir", "폴더(짧게)"), ("path", "경로(전체)"),
        ("ctx", "컨텍스트"), ("5h", "5시간"), ("wk", "주간"),
        ("git", "git"), ("tool", "도구"), ("agent", "에이전트"), ("cost", "비용")
    ]

    /// 항목별 기본 행 번호 (멀티라인 모드)
    static let defaultFieldRows: [String: Int] = [
        "ver": 0, "model": 0, "action": 0, "sid": 0, "dir": 0, "path": 0,
        "ctx": 1, "5h": 1, "wk": 1,
        "git": 2, "tool": 2, "agent": 2, "cost": 2
    ]

    /// 항목 색상 선택지: (식별자, 한글 라벨)
    static let colorOptions: [(id: String, label: String)] = [
        ("auto", "자동"), ("blue", "파랑"), ("purple", "보라"), ("green", "초록"),
        ("yellow", "노랑"), ("cyan", "청록"), ("orange", "주황"), ("red", "빨강"), ("gray", "회색")
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
    /// 렌더러가 읽는 표시 옵션 파일(JSON)
    private let hudOptsPath = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claudemonitor/hud-opts.json")
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
        try? writeOptsFile()
    }

    // MARK: - Registration

    func register() throws {
        try FileManager.default.createDirectory(at: monitorDir, withIntermediateDirectories: true)
        try writeHUDScript()
        try writeRenderScript()
        try? writeOptsFile()

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

    /// hud-render.mjs — statusLine JSON 을 파싱해 HUD 를 ANSI 컬러로 출력한다.
    /// 항목별 색상·행 번호를 hud-opts.json 에서 읽어 반영한다.
    private func writeRenderScript() throws {
        let script = """
        import fs from 'fs';
        import { execSync } from 'child_process';

        let raw = '';
        try { raw = fs.readFileSync(0, 'utf8'); } catch { process.exit(0); }
        let d;
        try { d = JSON.parse(raw); } catch { process.exit(0); }

        const E = String.fromCharCode(27);
        const R = E + '[0m';
        const NL = String.fromCharCode(10);

        const DIR = (process.env.HOME || '') + '/.claudemonitor';
        let opt = { emoji: true, filled: true, multiline: false, fields: null, fieldRows: {}, fieldColors: {} };
        try { opt = Object.assign(opt, JSON.parse(fs.readFileSync(DIR + '/hud-opts.json', 'utf8'))); } catch { }
        const emoji = !!opt.emoji, filled = !!opt.filled, multiline = !!opt.multiline;
        const fields = Array.isArray(opt.fields) ? opt.fields : null;
        const fieldRows = (opt.fieldRows && typeof opt.fieldRows === 'object') ? opt.fieldRows : {};
        const fieldColors = (opt.fieldColors && typeof opt.fieldColors === 'object') ? opt.fieldColors : {};

        // 색상 이름 → [bg, fg, tint] (ANSI 256)
        const COLOR_PRESETS = {
          blue:    [24,  159,  39],
          purple:  [54,  225, 141],
          gray:    [240, 255, 245],
          red:     [88,  203, 203],
          green:   [22,  120,  35],
          yellow:  [58,  229, 178],
          cyan:    [23,  159,  43],
          orange:  [130, 230, 215],
          magenta: [90,  219, 198],
        };

        // 항목별 기본 행 번호
        const DEFAULT_ROWS = {
          'ver':0,'model':0,'action':0,'sid':0,'dir':0,'path':0,
          'ctx':1,'5h':1,'wk':1,
          'git':2,'tool':2,'agent':2,'cost':2
        };

        // 사용률 레벨 → [채움 배경, 채움 전경, tint(밝은 전경)]
        const lvl = (p) => (p >= 80 ? [52, 210, 203] : p >= 50 ? [58, 229, 178] : [22, 120, 35]);

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
            const lines = buf.toString('utf8').split(NL).filter(Boolean);
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

        const fmtReset = (ts) => {
          if (!ts) return '';
          const ms = ts * 1000 - Date.now();
          if (ms <= 0) return '';
          const m = Math.floor(ms / 60000);
          return m >= 60 ? (' ' + Math.floor(m / 60) + 'h') : (' ' + m + 'm');
        };

        // 각 세그먼트: { emoji, text, bg, fg, tint }
        const parts = {};
        const add = (key, e, text, bg, fg, tint) => { parts[key] = { emoji: e, text, bg, fg, tint }; };

        add('ver', '🔹', 'CC ' + (d.version || ''), 24, 159, 39);
        const model = (d.model && (d.model.display_name || d.model.id)) || '';
        if (model) add('model', '🧠', model, 54, 225, 141);
        if (action) add('action', '▶️', action, 240, 255, 245);
        const sid = (d.session_id || '').slice(0, 6);
        if (sid) add('sid', '🔖', '#' + sid, 236, 247, 244);
        const cwdPath = (d.workspace && d.workspace.current_dir) || d.cwd || '';
        if (cwdPath) {
          const segs = cwdPath.split('/').filter(Boolean);
          add('dir',  '📁', segs.slice(-2).join('/'), 60, 200, 180);
          add('path', '📂', cwdPath, 60, 200, 180);
        }
        const cw = d.context_window;
        if (cw && typeof cw.used_percentage === 'number') {
          const L = lvl(cw.used_percentage);
          add('ctx', '📊', 'ctx ' + Math.round(cw.used_percentage) + '%', L[0], L[1], L[2]);
        }
        const rate = (key, e, label, o) => {
          if (!o || typeof o.used_percentage !== 'number') return;
          const L = lvl(o.used_percentage);
          add(key, e, label + ' ' + Math.round(o.used_percentage) + '%' + fmtReset(o.resets_at), L[0], L[1], L[2]);
        };
        const rl = d.rate_limits || {};
        rate('5h', '⏱️', '5h', rl.five_hour);
        rate('wk', '📅', 'wk', rl.seven_day);
        let branch = '';
        try {
          const dir = (d.workspace && d.workspace.current_dir) || d.cwd || '.';
          branch = execSync('git -C "' + dir + '" rev-parse --abbrev-ref HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
        } catch { }
        if (branch) add('git', '🌿', 'git ' + branch, 23, 159, 43);
        if (tool) add('tool', '🔧', 'tool ' + tool, 25, 159, 75);
        if (agent) add('agent', '🤖', '@' + agent, 130, 230, 215);
        if (d.cost && typeof d.cost.total_cost_usd === 'number') add('cost', '💰', '$' + d.cost.total_cost_usd.toFixed(2), 238, 191, 108);

        const ALL = ['ver', 'model', 'action', 'sid', 'dir', 'path', 'ctx', '5h', 'wk', 'git', 'tool', 'agent', 'cost'];
        const selKeys = ALL.filter((k) => parts[k] && (!fields || fields.indexOf(k) >= 0));

        const fgc = (c, t) => E + '[38;5;' + c + 'm' + t + R;

        // 항목별 색상 결정 (per-item override)
        const resolveColor = (k) => {
          const name = fieldColors[k];
          return (name && name !== 'auto' && COLOR_PRESETS[name]) ? COLOR_PRESETS[name] : null;
        };

        const seg = (k) => {
          const p = parts[k];
          const ov = resolveColor(k);
          const bg = ov ? ov[0] : p.bg;
          const fg = ov ? ov[1] : p.fg;
          const tint = ov ? ov[2] : p.tint;
          const label = (emoji && p.emoji ? p.emoji + ' ' : '') + p.text;
          if (filled) return E + '[48;5;' + bg + 'm' + E + '[38;5;' + fg + 'm ' + label + ' ' + R;
          return fgc(tint, label);
        };
        const sep = filled ? '' : (E + '[90m' + '  ·  ' + R);

        let out;
        if (multiline) {
          // 항목별 행 번호로 그루핑
          const rowMap = {};
          for (const k of selKeys) {
            const row = (k in fieldRows) ? fieldRows[k] : (DEFAULT_ROWS[k] !== undefined ? DEFAULT_ROWS[k] : 0);
            if (!rowMap[row]) rowMap[row] = [];
            rowMap[row].push(k);
          }
          const sortedRows = Object.keys(rowMap).map(Number).sort((a, b) => a - b);
          out = sortedRows.map((r) => rowMap[r].map(seg).join(sep)).join(NL);
        } else {
          out = selKeys.map(seg).join(sep);
        }
        process.stdout.write(out);
        """
        try script.write(to: renderScriptPath, atomically: true, encoding: .utf8)
    }

    /// 두 행의 번호를 서로 교환한다 (행 순서 변경용). 단일 assignment로 처리해 didSet 1회만 발생.
    func swapRows(_ a: Int, _ b: Int) {
        guard a != b else { return }
        var updated = hudFieldRows
        for f in ClaudeCodeHUDConnector.availableFields {
            let cur = updated[f.id] ?? ClaudeCodeHUDConnector.defaultFieldRows[f.id] ?? 0
            if cur == a { updated[f.id] = b }
            else if cur == b { updated[f.id] = a }
        }
        hudFieldRows = updated
    }

    /// 표시 옵션을 hud-opts.json 에 기록한다. 렌더러가 매 렌더마다 읽는다.
    private func writeOptsFile() throws {
        try FileManager.default.createDirectory(at: monitorDir, withIntermediateDirectories: true)
        let orderedFields = ClaudeCodeHUDConnector.availableFields
            .map { $0.id }.filter { hudFields.contains($0) }
        let opts: [String: Any] = [
            "emoji": hudEmoji,
            "filled": hudFilled,
            "multiline": true,
            "fields": orderedFields,
            "fieldRows": hudFieldRows,
            "fieldColors": hudFieldColors
        ]
        let data = try JSONSerialization.data(withJSONObject: opts, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: hudOptsPath, options: .atomic)
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
