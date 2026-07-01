# ClaudeMonitor

Claude Code와 OpenAI Codex의 토큰 사용량을 실시간으로 추적하고, 그 활동을 **사용패턴 회고**로 바꿔주는 macOS 메뉴바 앱입니다. 대화 내용은 저장하지 않고 "어떻게 작업하는지"만 조용히 기록해 두었다가, 원할 때 또는 주기적으로 Claude가 그 습관을 되짚어 알려줍니다.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![Version](https://img.shields.io/badge/version-1.5.1-green)

[English](README.md) · **한국어**

---

## 주요 기능

- **사용패턴 회고** — 실제 작업 세션(봇/자동화는 제외)을 분석해 헤드리스 `claude -p`로 회고를 생성. **기본 회고**(근거 기반 코칭)와 **갱생 회고**(사정없이 굽는 버전) 두 유형. 수동 "지금 생성" 또는 주기 자동 생성, 새 회고가 준비되면 메뉴바 아이콘에 배지 표시. API 키 불필요 — 로그인된 Claude Code를 그대로 사용
- **메뉴바 실시간 통계** — 5시간 롤링 창과 주간 사용량을 물탱크 게이지로 표시
- **토큰 속도 표시기** — 쌓인 막대 게이지로 현재 처리량 시각화 (없음 → 보통 → 많음 → 폭발적), 임계값 직접 설정 또는 자동 계산
- **Claude Code HUD** — `statusLine` 제공자로 자동 등록; 모델·상태·컨텍스트 %·사용률 막대·git 브랜치·현재 도구·사고량·작업 폴더·비용을 프롬프트에 직접 렌더링
- **HUD 레이아웃 커스터마이즈** — 항목을 드래그 앤 드롭으로 행 간 이동, 행 내 칩 순서 변경, 항목별 색상 지정(자동 또는 8가지 프리셋); 단일/멀티라인 스타일
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

## Xcode로 실행하기

**준비물:** macOS 13+, Xcode 15+, 그리고 [XcodeGen](https://github.com/yonaskolb/XcodeGen)(`brew install xcodegen`). Xcode 프로젝트는 `project.yml`에서 생성되므로, 클론 직후나 파일을 추가할 때마다 다시 생성합니다.

```bash
git clone https://github.com/xivicWon/ai-usage-snipping.git
cd ai-usage-snipping
xcodegen generate            # project.yml → ClaudeMonitor.xcodeproj 생성
open ClaudeMonitor.xcodeproj
```

Xcode에서:

1. 상단 툴바에서 **ClaudeMonitor** 스킴과 실행 대상 **My Mac**을 선택합니다.
2. **⌘R**(Product ▸ Run)을 누릅니다.
3. ClaudeMonitor는 **메뉴바(accessory) 앱이라 실행해도 Dock 아이콘이나 창이 없습니다.** **화면 우상단 메뉴바**의 아이콘을 찾아 클릭하면 팝오버가 열리고, *대시보드 열기*로 회고/차트 창을 엽니다.
4. 종료하려면 Xcode에서 **⌘.** (또는 팝오버의 *종료*).

테스트는 **⌘U**, 또는 커맨드라인:

```bash
xcodebuild test -scheme ClaudeMonitor -destination 'platform=macOS'
```

Xcode 없이 릴리스 빌드(ad-hoc 서명):

```bash
xcodebuild -scheme ClaudeMonitor -configuration Release build
# 또는 배포용 .dmg 생성:
./scripts/build-dmg.sh
```

> **서명 참고:** 릴리스는 ad-hoc 서명(Apple 개발자 계정 없음)입니다. 첫 실행 시 Gatekeeper가 막으면 앱 **우클릭 ▸ 열기**, 또는 `xattr -dr com.apple.quarantine /Applications/ClaudeMonitor.app`. macOS 시스템 알림도 정식 서명이 필요해, "새 회고" 알림은 대신 메뉴바 배지로 표시됩니다.

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
🔹 CC 1.x  🧠 claude-opus-4  ▶️ running  🧩 effort high  📊 ctx 42%  ⏱️ 5h 28%  📅 wk 15%  🌿 git main  💰 $0.12
```

표시 가능한 항목: CC 버전, 모델, 상태, 세션, 폴더(짧게), 경로(전체), 컨텍스트, 5시간, 주간, git, 도구, 에이전트, 비용, 사고량(effort). 레이아웃은 **설정 → Claude → HUD 표시**에서 커스터마이즈합니다:

- **드래그 앤 드롭 레이아웃** — 항목을 행 간 이동, 행 내 칩 순서 변경
- **항목별 색상** — `자동`(값에 따라 동적) 또는 8가지 프리셋(파랑·보라·초록·노랑·청록·주황·빨강·회색)
- **표시 스타일** — 이모지 on/off, 채움/아웃라인 막대, 단일/멀티라인

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

## 사용패턴 회고

대시보드의 **🪞 회고** 탭은 기록된 활동을 *AI를 어떻게 쓰는지*에 대한 되돌아보기로 바꿔줍니다.

- **무엇을 쓰나** — 세션당 작은 파생 신호만(목표 수, 도구 믹스, 편집 파일, 에러, 중도 중단, 토큰, 시간대). **대화 내용은 저장하지 않습니다.** 봇/자동화 세션(서브에이전트 오케스트레이션, 리뷰봇, `.claude-brief` 실행)은 자동 식별해 제외하므로 통계가 *당신의* 작업을 반영합니다.
- **어떻게 생성하나** — 집계된 통계를 헤드리스 `claude -p`(로그인된 Claude Code — API 키 불필요, 실행당 1콜)로 보냅니다. 기간(1일 / 3일 / 7일)과 유형을 고르고 **지금 생성**, 또는 주기 자동 생성.
- **두 가지 유형**
  - **기본 회고** — 근거 기반 코칭. 개선점마다 구체 수치를 인용해야 하고 뻔한 일반론은 금지.
  - **갱생 회고** — "나에 대해 아는 걸 근거로 사정없이 굽는" 회고. 실제 수치에 근거함.
- **어디서 보나** — 탭에서 마크다운으로 읽고, 히스토리 사이드바에서 지난 회고를 훑고, **복사** 버튼으로 클립보드에 담습니다. 주기 회고가 준비되면 확인할 때까지 메뉴바 아이콘과 *회고* 항목에 초록 점이 표시됩니다.

주기는 **설정 → 회고**에서: 끔 / 매일 / 3일 / 매주. 모든 처리는 로컬에서 이루어지며 업로드되는 것은 없습니다.

## 설정

| 탭 | 옵션 |
|----|------|
| Claude | Claude 모니터링 사용/중지 |
| Claude | HUD 연결 — 등록·해제·기존 HUD와 체이닝 |
| Claude | HUD 레이아웃 — 드래그 앤 드롭 항목 배치, 항목별 색상, 단일/멀티라인 스타일 |
| Claude | 토큰 속도 게이지 임계값 (직접 설정 또는 자동 계산) |
| Codex | Codex 모니터링 사용/중지 |
| Codex | 커스텀 `~/.codex` 홈 경로 |
| 회고 | 회고 주기(끔 / 매일 / 3일 / 매주) + 새 회고 알림 토글 |

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

# 회고 파이프라인
~/.claude/projects/**/*.jsonl
         │ ClaudeSessionFeatureParser  (텍스트 버림, 봇 플래그)
         ▼
    SessionFeatureStore (features.sqlite)
         │ RetrospectiveAggregator (사람 세션만)
         ▼
    RetrospectivePromptBuilder → claude -p → RetrospectiveReportStore
         ▲                                          │
    스케줄러 / "지금 생성"                    대시보드 회고 탭
```

PlantUML 아키텍처·데이터플로우·스키마 다이어그램은 [`docs/diagrams/`](docs/diagrams/)를 참고하세요.

## 라이선스

MIT
