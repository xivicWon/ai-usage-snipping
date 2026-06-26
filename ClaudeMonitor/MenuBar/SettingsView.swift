// ClaudeMonitor/MenuBar/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var limits = UsageLimits.shared

    var body: some View {
        TabView {
            claudeTab
                .tabItem { Label("Claude", systemImage: "sparkle") }
            codexTab
                .tabItem { Label("Codex", systemImage: "terminal") }
        }
        .frame(width: 460, height: 280)
        .padding()
    }

    // MARK: - Claude tab

    private var claudeTab: some View {
        Form {
            Section("계정") {
                TextField("이메일", text: $limits.accountEmail)
            }
            Section("토큰 한도 (0 = 미설정)") {
                HStack {
                    Text("5시간 창")
                    Spacer()
                    TextField("토큰", value: $limits.windowLimitTokens, format: .number)
                        .frame(width: 120)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("주간")
                    Spacer()
                    TextField("토큰", value: $limits.weeklyLimitTokens, format: .number)
                        .frame(width: 120)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Codex tab

    private var codexTab: some View {
        Form {
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
