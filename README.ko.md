# ClaudeMonitor

Claude Code와 OpenAI Codex의 토큰 사용량을 실시간으로 추적하는 macOS 메뉴바 앱입니다.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![Version](https://img.shields.io/badge/version-1.1.3-green)

[English](README.md) · **한국어**

---

## 주요 기능

- **메뉴바 실시간 통계** — 5시간 롤링 창과 주간 사용량을 물탱크 게이지로 표시
- **토큰 속도 표시기** — 쌓인 막대 게이지로 현재 처리량 시각화 (없음 → 보통 → 많음 → 폭발적)
- **Claude Code HUD** — `statusLine` 제공자로 자동 등록; 모델·상태·컨텍스트 %·사용률 막대·git 브랜치·현재 도구·비용을 프롬프트에 직접 렌더링
- **Codex 지원** — `~/.codex` 세션 아카이브를 읽어 오늘/주간 토큰 수를 Claude와 나란히 표시
- **대시보드 창** — 세션 목록, 일간/주간 차트, 프로젝트별 통계 (Claude·Codex 모두)
- **실시간 파일 감시** — FSEvent 기반; Claude Code가 JSONL을 쓰는 즉시 반영
- **`cm-status` CLI** — SQLite를 직접 쿼리해 5시간/오늘/주간 토큰 수를 출력 (텍스트 또는 JSON)
- **멀티 프로필** — Claude 계정별로 별도 SQLite DB를 유지하며 전환 가능
- **HUD 자동 탐색** — OMC 등 다른 도구의 HUD 캐시를 투명하게 읽어 재설정 없이 동작

## 요구 사항

- macOS 13 Ventura 이상
- Xcode 15 (소스 빌드 시)

## 설치

[Releases](../../releases)에서 최신 `ClaudeMonitor-x.x.x.dmg`를 내려받아 열고 **ClaudeMonitor**를 Applications에 드래그합니다.

최초 실행 시 앱이 자동으로:
1. 메뉴바에 아이콘을 추가합니다
2. Claude Code `statusLine`에 HUD를 등록합니다 (슬롯이 비어있을 때만)
3. `~/.claude/projects`의 기존 세션 기록을 전체 스캔합니다

## 소스 빌드

```bash
git clone https://github.com/xivic/claude-monitor.git
cd claude-monitor
xcodegen generate          # 필요: brew install xcodegen
open ClaudeMonitor.xcodeproj
```

또는 커맨드라인에서:

```bash
xcodebuild -scheme ClaudeMonitor -configuration Release build
```

## 메뉴바

아이콘을 클릭하면 팝오버가 열립니다:

| 요소 | 설명 |
|------|------|
| 물탱크 (5시간 창) | 현재 5시간 속도 제한 창의 남은 용량 |
| 물탱크 (주간) | 7일 주기의 남은 용량 |
| 쌓인 막대 게이지 | 실시간 토큰 속도: 초록 → 주황 → 빨강 |
| 리셋 타이머 | 다음 창/주간 리셋까지 남은 시간 |
| Codex 바 | 5시간 사용률 % 및 오늘/주간 토큰 수 (Codex 활성 시) |

색상 기준 (탱크와 메뉴바 아이콘 모두 동일):
- **초록** 50 % 이상 남음
- **주황** 20–50 % 남음
- **빨강** 20 % 미만 남음

## Claude Code HUD

앱이 `~/.claudemonitor/hud.sh`를 기록하고 `~/.claude/settings.json`의 `statusLine`에 등록합니다. Claude Code가 프롬프트를 렌더링할 때마다:

1. 세션 JSON을 `~/.claudemonitor/hud-cache.json`에 저장 (메뉴바 앱이 이 파일을 읽음)
2. `hud-render.mjs`로 한 줄 상태를 렌더링:

```
🔹 CC 1.x  🧠 claude-opus-4  ▶️ running  📊 ctx 42%  ⏱️ 5h 28%  📅 wk 15%  🌿 git main  💰 $0.12
```

표시할 항목과 스타일(이모지 on/off, 채움/아웃라인, 단일/멀티라인)은 **설정 → Claude → HUD 표시**에서 설정합니다.

다른 도구(예: OMC)가 이미 `statusLine`을 점유하고 있으면 ClaudeMonitor는 뒤에 체이닝되어 함께 공존합니다.

## `cm-status` CLI

`scripts/cm-status`를 PATH에 복사합니다:

```bash
cp scripts/cm-status /usr/local/bin/cm-status
chmod +x /usr/local/bin/cm-status
```

사용법:

```bash
cm-status           # 텍스트 요약
cm-status --json    # JSON 출력 (파이프 친화적)
```

출력 예시:

```
5h  window :    142381 tokens
This week  :    891204 tokens
Today      :    203455 tokens  ($0.8821)
```

앱은 `~/Library/Application Support/ClaudeMonitor/active.sqlite`를 현재 프로필 DB의 심볼릭 링크로 유지하므로 외부 스크립트에서 항상 동일한 경로로 조회할 수 있습니다.

## 설정

| 탭 | 옵션 |
|----|------|
| Claude | Claude 모니터링 사용/중지 |
| Claude | HUD 연결 — 등록·해제·기존 HUD와 체이닝 |
| Claude | HUD 표시 항목 및 스타일 |
| Codex | Codex 모니터링 사용/중지 |
| Codex | 커스텀 `~/.codex` 홈 경로 |

## 아키텍처

```
~/.claude/projects/**/*.jsonl   (Claude Code 기록)
         │
         ▼ FSEventWatcher
    JSONLParser → SQLiteStore (GRDB)
         │
         ▼ Combine 퍼블리셔
    AppState → SwiftUI 뷰 (MenuBarView, DashboardView)

~/.claudemonitor/hud-cache.json (hud.sh를 통해 Claude Code CLI가 기록)
         │
         ▼ 파일 디스크립터 감시자
    AnthropicUsageReader → 속도 제한 오버레이
```

PlantUML 아키텍처·데이터플로우·스키마 다이어그램은 [`docs/diagrams/`](docs/diagrams/)를 참고하세요.

## 라이선스

MIT
