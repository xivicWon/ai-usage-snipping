// ClaudeMonitor/App/ClaudeMonitorApp.swift
import SwiftUI
import AppKit
import Combine

@main
struct ClaudeMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var dashboardWindow: NSWindow?
    private let appState = AppState()
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = Self.makeClaudeIcon()
            button.title = " --"
            button.action = #selector(togglePopover)
            button.target = self
        }

        let pop = NSPopover()
        pop.contentSize = NSSize(width: 260, height: 240)
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(
            rootView: MenuBarView(openDashboard: { [weak self] in self?.openDashboard() })
                .environmentObject(appState)
        )
        popover = pop

        // Update title from Anthropic usage cache (real quota %) or token count fallback
        cancellable = AnthropicUsageReader.shared.$usage
            .combineLatest(appState.$windowTokens)
            .receive(on: RunLoop.main)
            .sink { [weak self] usage, tokens in
                guard let self else { return }
                let title: String
                if let u = usage {
                    title = String(format: " %.0f%%", u.fiveHourRemaining * 100)
                } else {
                    title = " \(Self.formatTokens(tokens))"
                }
                self.statusItem?.button?.title = title
            }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let pop = popover else { return }
        if pop.isShown {
            pop.performClose(nil)
        } else {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func openDashboard() {
        popover?.performClose(nil)
        if let w = dashboardWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Claude Monitor"
        w.center()
        w.contentViewController = NSHostingController(
            rootView: DashboardView().environmentObject(appState)
        )
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow = w
    }

    /// Claude-inspired menu bar icon: C-arc + small sparkle dot.
    static func makeClaudeIcon() -> NSImage {
        let sz: CGFloat = 18
        let img = NSImage(size: NSSize(width: sz, height: sz), flipped: false) { bounds in
            let cx = bounds.midX, cy = bounds.midY
            let r: CGFloat = 7.2

            // Outer C-arc (open right, ~270°)
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: cx, y: cy),
                          radius: r, startAngle: 45, endAngle: 315, clockwise: false)
            arc.lineWidth = 2
            arc.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            arc.stroke()

            // Three small dots arranged vertically on the open side (right edge) — Claude's "signal bars"
            let dotR: CGFloat = 1.2
            let dotX = cx + r * cos(0 * .pi / 180)
            for (i, dy) in [CGFloat(3), CGFloat(0), CGFloat(-3)].enumerated() {
                let alpha: CGFloat = i == 1 ? 1.0 : 0.45
                NSColor.labelColor.withAlphaComponent(alpha).setFill()
                NSBezierPath(ovalIn: NSRect(x: dotX - dotR, y: cy + dy - dotR,
                                            width: dotR * 2, height: dotR * 2)).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    static func formatTokens(_ n: Int) -> String {
        switch n {
        case 0..<1_000: return "\(n) tok"
        case 1_000..<1_000_000: return String(format: "%.1fK tok", Double(n) / 1_000)
        default: return String(format: "%.1fM tok", Double(n) / 1_000_000)
        }
    }
}
