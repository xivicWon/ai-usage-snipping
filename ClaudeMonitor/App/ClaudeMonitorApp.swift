// ClaudeMonitor/App/ClaudeMonitorApp.swift
import SwiftUI
import AppKit
import Combine

@main
struct ClaudeMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { SettingsView() }
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
            button.imagePosition = .imageLeft
            button.title = " --"
            button.action = #selector(togglePopover)
            button.target = self
        }

        let pop = NSPopover()
        pop.behavior = .transient
        let menuView = MenuBarView(openDashboard: { [weak self] in self?.openDashboard() })
            .environmentObject(appState)
        let hc = NSHostingController(rootView: menuView)
        if #available(macOS 13.0, *) {
            hc.sizingOptions = .preferredContentSize
        }
        pop.contentViewController = hc
        popover = pop

        // Combine Claude + Codex signals → update status bar item
        cancellable = AnthropicUsageReader.shared.$usage
            .combineLatest(CodexSessionReader.shared.$primaryUsedPercent)
            .combineLatest(CodexSessionReader.shared.$sessions.map { !$0.isEmpty })
            .receive(on: RunLoop.main)
            .sink { [weak self] combined, codexConnected in
                guard let self else { return }
                let (usage, codexUsedPct) = combined

                let claudeRemaining: Double? = usage?.fiveHourRemaining
                let codexPct: Double? = codexConnected ? codexUsedPct : nil

                guard let button = self.statusItem?.button else { return }

                if claudeRemaining != nil || codexPct != nil {
                    button.image = Self.makeStatusBarImage(
                        claudeRemaining: claudeRemaining,
                        codexUsedPercent: codexPct
                    )
                    button.imagePosition = .imageOnly
                    button.title = ""
                } else {
                    button.image = Self.makeClaudeIcon()
                    button.imagePosition = .imageLeft
                    button.title = " --"
                }
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
        w.isReleasedWhenClosed = false
        w.title = "Claude Monitor"
        w.center()
        w.contentViewController = NSHostingController(
            rootView: DashboardView().environmentObject(appState)
        )
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow = w
    }

    // MARK: - Status bar image

    /// Two-column mini stat: [Claude / Codex] each with small label on top + big % below.
    static func makeStatusBarImage(claudeRemaining: Double?, codexUsedPercent: Double?) -> NSImage {
        let colW: CGFloat = 44
        let gap:  CGFloat = 6
        let showClaude = claudeRemaining != nil
        let showCodex  = codexUsedPercent != nil
        let cols = (showClaude ? 1 : 0) + (showCodex ? 1 : 0)
        let width = CGFloat(cols) * colW + CGFloat(max(0, cols - 1)) * gap
        let height: CGFloat = 22

        let img = NSImage(size: NSSize(width: max(width, 30), height: height), flipped: false) { _ in
            var x: CGFloat = 0

            if let pct = claudeRemaining {
                let valColor: NSColor = pct >= 0.5 ? .systemGreen : pct >= 0.2 ? .systemOrange : .systemRed
                Self.drawStat(
                    label: "Claude",
                    value: String(format: "%.0f%%", pct * 100),
                    atX: x, colW: colW, height: height,
                    labelColor: .systemOrange,
                    valueColor: valColor
                )
                x += colW + gap
            }

            if let usedPct = codexUsedPercent {
                let valColor: NSColor = usedPct < 50 ? .systemBlue : usedPct < 80 ? .systemOrange : .systemRed
                Self.drawStat(
                    label: "Codex",
                    value: String(format: "%.0f%%", usedPct),
                    atX: x, colW: colW, height: height,
                    labelColor: .systemBlue,
                    valueColor: valColor
                )
            }

            return true
        }
        img.isTemplate = false
        return img
    }

    private static func drawStat(label: String, value: String,
                                  atX x: CGFloat, colW: CGFloat, height: CGFloat,
                                  labelColor: NSColor, valueColor: NSColor) {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7, weight: .semibold),
            .foregroundColor: labelColor
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: valueColor
        ]

        let labelNS = label as NSString
        let valueNS = value as NSString

        let labelSz = labelNS.size(withAttributes: labelAttrs)
        let valueSz = valueNS.size(withAttributes: valueAttrs)

        let labelX = x + (colW - labelSz.width) / 2
        let valueX = x + (colW - valueSz.width) / 2

        // label at top, value just below
        labelNS.draw(at: NSPoint(x: labelX, y: height - labelSz.height + 1), withAttributes: labelAttrs)
        valueNS.draw(at: NSPoint(x: valueX, y: 1), withAttributes: valueAttrs)
    }

    // MARK: - Fallback icon (Claude C-arc)

    static func makeClaudeIcon() -> NSImage {
        let sz: CGFloat = 18
        let img = NSImage(size: NSSize(width: sz, height: sz), flipped: false) { bounds in
            let cx = bounds.midX, cy = bounds.midY
            let r: CGFloat = 7.2

            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: cx, y: cy),
                          radius: r, startAngle: 45, endAngle: 315, clockwise: false)
            arc.lineWidth = 2
            arc.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            arc.stroke()

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
}
