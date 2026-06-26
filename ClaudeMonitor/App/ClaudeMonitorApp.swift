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
            button.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Claude Monitor")
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

        // Update title whenever window-usage or the configured limit changes
        cancellable = appState.$windowTokens
            .combineLatest(appState.limits.$windowLimitTokens)
            .receive(on: RunLoop.main)
            .sink { [weak self] tokens, limit in
                guard let self else { return }
                let title: String
                if let pct = UsageLimits.shared.percentRemaining(used: tokens, limit: limit) {
                    title = String(format: " %.0f%% 남음", pct * 100)
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

    static func formatTokens(_ n: Int) -> String {
        switch n {
        case 0..<1_000: return "\(n) tok"
        case 1_000..<1_000_000: return String(format: "%.1fK tok", Double(n) / 1_000)
        default: return String(format: "%.1fM tok", Double(n) / 1_000_000)
        }
    }
}
