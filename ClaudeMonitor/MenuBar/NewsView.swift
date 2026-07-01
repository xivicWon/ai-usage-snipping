// ClaudeMonitor/MenuBar/NewsView.swift
import SwiftUI
import AppKit

struct NewsView: View {
    @StateObject private var vm = NewsViewModel()
    @State private var didCopy = false

    var body: some View {
        HSplitView {
            historySidebar.frame(minWidth: 170, maxWidth: 210)
            detail
        }
        .onAppear { NewsBadge.shared.markSeen() }
    }

    // MARK: - History sidebar

    private var historySidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("지난 뉴스").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if vm.digests.isEmpty {
                Spacer()
                Text("아직 뉴스가 없습니다").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(vm.digests) { d in
                            historyRow(d)
                            Divider()
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func historyRow(_ d: NewsDigest) -> some View {
        let isSel = vm.selected?.id == d.id
        return VStack(alignment: .leading, spacing: 2) {
            Text(Self.dateFmt.string(from: d.generatedAt))
                .font(.system(size: 12, weight: .medium))
            Text("\(d.sourceCount)개 소스 · \(d.itemCount)건 수집")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(isSel ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { vm.selected = d }
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    vm.generateNow()
                } label: {
                    if vm.isGenerating {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("수집·요약 중…") }
                    } else {
                        Label("지금 생성", systemImage: "newspaper")
                    }
                }
                .disabled(vm.isGenerating || !vm.isAvailable)
                Spacer()

                Button {
                    copySelected()
                } label: {
                    Label(didCopy ? "복사됨" : "복사", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .disabled(vm.selected == nil)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()

            if let msg = vm.errorMessage {
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .padding(.horizontal, 16).padding(.vertical, 8)
            }

            if let digest = vm.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Self.dateFmt.string(from: digest.generatedAt)) · \(digest.sourceCount)개 소스 · \(digest.itemCount)건 수집")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                        MarkdownText(digest.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            } else {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "newspaper").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text(vm.isAvailable ? "‘지금 생성’을 눌러 오늘의 AI 뉴스 한줄요약을 받아보세요"
                                        : "claude CLI를 찾을 수 없어 생성할 수 없습니다")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }

    /// 선택된 다이제스트 본문을 클립보드로 복사.
    private func copySelected() {
        guard let body = vm.selected?.body else { return }
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
