// ClaudeMonitor/MenuBar/RetrospectiveView.swift
import SwiftUI

struct RetrospectiveView: View {
    @StateObject private var vm = RetrospectiveViewModel()

    var body: some View {
        HSplitView {
            historySidebar.frame(minWidth: 170, maxWidth: 210)
            detail
        }
        .onAppear { RetroBadge.shared.markSeen() }
    }

    // MARK: - History sidebar

    private var historySidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("지난 회고").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if vm.reports.isEmpty {
                Spacer()
                Text("아직 회고가 없습니다").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(vm.reports) { r in
                            historyRow(r)
                            Divider()
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func historyRow(_ r: RetrospectiveReport) -> some View {
        let isSel = vm.selected?.id == r.id
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if r.style == .roast {
                    Text("갱생").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.red).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.red.opacity(0.12)).clipShape(Capsule())
                }
                Text(r.periodLabel).font(.system(size: 12, weight: .medium))
            }
            Text(Self.dateFmt.string(from: r.generatedAt))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(isSel ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { vm.selected = r }
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: $vm.period) {
                    ForEach(RetroPeriod.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu).frame(width: 110).disabled(vm.isGenerating)

                Picker("", selection: $vm.style) {
                    ForEach(RetroStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu).frame(width: 110).disabled(vm.isGenerating)

                Button {
                    vm.generateNow()
                } label: {
                    if vm.isGenerating {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("생성 중…") }
                    } else {
                        Label("지금 생성", systemImage: "sparkles")
                    }
                }
                .disabled(vm.isGenerating || !vm.isAvailable)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()

            if let msg = vm.errorMessage {
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .padding(.horizontal, 16).padding(.vertical, 8)
            }

            if let report = vm.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(report.style.label) · \(report.periodLabel) · \(Self.dateFmt.string(from: report.generatedAt))")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                        MarkdownText(report.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            } else {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text(vm.isAvailable ? "기간을 고르고 ‘지금 생성’을 눌러보세요"
                                        : "claude CLI를 찾을 수 없어 생성할 수 없습니다")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d a h:mm"; return f
    }()
}

/// ## 제목 · - 리스트 · 인라인 볼드만 처리하는 가벼운 마크다운 렌더러.
struct MarkdownText: View {
    let raw: String
    init(_ raw: String) { self.raw = raw }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(raw.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("## ") {
            Text(inline(String(t.dropFirst(3)))).font(.system(size: 14, weight: .bold)).padding(.top, 6)
        } else if t.hasPrefix("# ") {
            Text(inline(String(t.dropFirst(2)))).font(.system(size: 16, weight: .bold)).padding(.top, 6)
        } else if t.hasPrefix("- ") || t.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(String(t.dropFirst(2))))
            }.font(.system(size: 12))
        } else if t.isEmpty {
            Spacer().frame(height: 2)
        } else {
            Text(inline(t)).font(.system(size: 12))
        }
    }

    /// 인라인 마크다운(**bold** 등)은 AttributedString 으로.
    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}
