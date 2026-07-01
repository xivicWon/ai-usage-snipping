// ClaudeMonitor/App/ClaudeMonitorApp.swift
import SwiftUI
import AppKit
import Combine
import UserNotifications

@main
struct ClaudeMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { SettingsView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var dashboardWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let appState = AppState()
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self

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
        let menuView = MenuBarView(
            openDashboard: { [weak self] in self?.openDashboard() },
            openSettings:  { [weak self] in self?.openSettings() }
        )
            .environmentObject(appState)
        let hc = NSHostingController(rootView: menuView)
        if #available(macOS 13.0, *) {
            hc.sizingOptions = .preferredContentSize
        }
        pop.contentViewController = hc
        popover = pop

        // Combine Claude + Codex signals (+ on/off 토글) → update status bar item
        cancellable = AnthropicUsageReader.shared.$usage
            .combineLatest(CodexSessionReader.shared.$primaryUsedPercent)
            .combineLatest(CodexSessionReader.shared.$sessions.map { !$0.isEmpty })
            .combineLatest(appState.$tokenRateLevel)
            .combineLatest(UsageLimits.shared.$claudeEnabled)
            .combineLatest(UsageLimits.shared.$codexEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] outer, codexEnabled in
                guard let self else { return }
                let (withRate, claudeEnabled) = outer
                let (combined2, rateLevel) = withRate
                let (combined1, codexConnected) = combined2
                let (usage, codexUsedPct) = combined1

                // 토글이 꺼진 쪽은 아이콘에서도 숨긴다
                let claudeRemaining: Double? = claudeEnabled ? usage?.fiveHourRemaining : nil
                let codexPct: Double? = (codexEnabled && codexConnected) ? codexUsedPct : nil

                guard let button = self.statusItem?.button else { return }

                if claudeRemaining != nil || codexPct != nil {
                    button.image = Self.makeStatusBarImage(
                        claudeRemaining: claudeRemaining,
                        codexUsedPercent: codexPct,
                        claudeRateLevel: rateLevel
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

    private func openSettings() {
        popover?.performClose(nil)
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.isReleasedWhenClosed = false
        w.title = "ClaudeMonitor 설정"
        w.center()
        w.contentViewController = NSHostingController(rootView: SettingsView())
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = w
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

    // MARK: - Notifications (회고 딥링크)

    /// 앱이 떠 있을 때도 배너를 보여준다.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// 알림 클릭 → 대시보드 회고 탭 열기(딥링크).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if info[RetroNotifier.deeplinkKey] as? String == RetroNotifier.deeplinkRetro {
            DashboardRouter.shared.requestedTool = DashboardView.AITool.retro.rawValue
            openDashboard()
        }
        completionHandler()
    }

    // MARK: - Status bar image

    /// Two-column mini stat: [Claude / Codex] each with small label on top + big % below.
    /// claudeRateLevel 0–3 draws a stacked bar gauge to the right of the Claude value.
    static func makeStatusBarImage(claudeRemaining: Double?, codexUsedPercent: Double?,
                                   claudeRateLevel: Int = 0) -> NSImage {
        let colW: CGFloat = 50    // wider to fit value + optional gauge bars
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
                    valueColor: valColor,
                    rateLevel: claudeRateLevel
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
                    valueColor: valColor,
                    rateLevel: 0
                )
            }

            return true
        }
        img.isTemplate = false
        return img
    }

    private static func drawStat(label: String, value: String,
                                  atX x: CGFloat, colW: CGFloat, height: CGFloat,
                                  labelColor: NSColor, valueColor: NSColor,
                                  rateLevel: Int = 0) {
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

        // Gauge bar dimensions (stacked vertically, drawn to the right of value)
        let barW: CGFloat = 3
        let barH: CGFloat = 3
        let barRowGap: CGFloat = 1.5
        let barSpacing: CGFloat = rateLevel > 0 ? 3 : 0
        let barAreaW: CGFloat = rateLevel > 0 ? barW : 0

        // Center value + bars as a group
        let groupW = valueSz.width + barSpacing + barAreaW
        let groupX = x + (colW - groupW) / 2
        let valueX = groupX
        let barX = groupX + valueSz.width + barSpacing

        // Label centered independently
        let labelX = x + (colW - labelSz.width) / 2
        labelNS.draw(at: NSPoint(x: labelX, y: height - labelSz.height + 1), withAttributes: labelAttrs)
        valueNS.draw(at: NSPoint(x: valueX, y: 1), withAttributes: valueAttrs)

        // Stacked bars: bottom=green(1), mid=orange(2), top=red(3)
        if rateLevel > 0 {
            let barColors: [NSColor] = [.systemGreen, .systemOrange, .systemRed]
            for i in 0..<3 {
                let barY = 1.5 + CGFloat(i) * (barH + barRowGap)
                let filled = i < rateLevel
                let color = filled ? barColors[i] : NSColor.secondaryLabelColor.withAlphaComponent(0.15)
                color.setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: barX, y: barY, width: barW, height: barH),
                    xRadius: 0.5, yRadius: 0.5
                ).fill()
            }
        }
    }

    // MARK: - Icons

    /// Codex icon: rounded terminal window + ">" cursor
    static func makeCodexIcon() -> NSImage {
        let sz: CGFloat = 18
        let img = NSImage(size: NSSize(width: sz, height: sz), flipped: false) { bounds in
            let cx = bounds.midX, cy = bounds.midY

            // Rounded square outline (terminal window)
            let rect = NSRect(x: 2.5, y: 2.5, width: sz - 5, height: sz - 5)
            let box = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            box.lineWidth = 1.5
            NSColor.labelColor.setStroke()
            box.stroke()

            // ">" prompt inside
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: cx - 2.5, y: cy + 3))
            arrow.line(to: NSPoint(x: cx + 2.5, y: cy))
            arrow.line(to: NSPoint(x: cx - 2.5, y: cy - 3))
            arrow.lineWidth = 1.5
            arrow.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            arrow.stroke()

            return true
        }
        img.isTemplate = true
        return img
    }

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
