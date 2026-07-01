// ClaudeMonitor/MenuBar/AdvisorView.swift
import SwiftUI
import AppKit

/// 라이브 어드바이저 조언 열람 뷰 (#27). 왼쪽 기록 · 오른쪽 본문.
struct AdvisorView: View {
    @State private var advices: [AdvisorAdvice] = []
    @State private var selected: AdvisorAdvice?
    @State private var didCopy = false

    var body: some View {
        HSplitView {
            historySidebar.frame(minWidth: 180, maxWidth: 220)
            detail
        }
        .onAppear {
            reload()
            AdvisorBadge.shared.markSeen()
        }
    }

    private func reload() {
        let store = try? AdvisorAdviceStore(path: AdvisorAdviceStore.defaultPath())
        advices = (try? store?.all()) ?? []
        if selected == nil { selected = advices.first }
    }

    // MARK: - History

    private var historySidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("받은 조언").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).font(.system(size: 11))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if advices.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "lightbulb").font(.system(size: 22)).foregroundStyle(.tertiary)
                    Text("아직 조언이 없습니다").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(advices) { a in
                            historyRow(a); Divider()
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func historyRow(_ a: AdvisorAdvice) -> some View {
        let isSel = selected?.id == a.id
        let cond = AdvisorCondition(rawValue: a.condition)
        return VStack(alignment: .leading, spacing: 2) {
            Text(cond?.label ?? a.condition)
                .font(.system(size: 12, weight: .medium))
            Text(Self.dateFmt.string(from: a.generatedAt))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(isSel ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selected = a }
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let a = selected, let cond = AdvisorCondition(rawValue: a.condition) {
                    Label(cond.label, systemImage: "lightbulb.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                }
                Spacer()
                Button { copySelected() } label: {
                    Label(didCopy ? "복사됨" : "복사", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .disabled(selected == nil)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()

            if let a = selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Self.dateFmt.string(from: a.generatedAt))
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                        MarkdownText(a.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            } else {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "lightbulb").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("문제 행동이 반복되면 조언이 여기에 표시됩니다")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }

    private func copySelected() {
        guard let body = selected?.body else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d a h:mm"; return f
    }()
}
