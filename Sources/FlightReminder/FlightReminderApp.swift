import AppKit
import SwiftUI

@MainActor
final class FlightReminderAppDelegate: NSObject, NSApplicationDelegate {
    private var qaPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--qa-preview") {
            showQAPreview()
        } else {
            ShortcutSettings.shared.activate()
            ReminderMonitor.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ShortcutSettings.shared.cancelRecording()
        GlobalHotKeyManager.shared.stop()
    }

    private func showQAPreview() {
        let monitor = ReminderMonitor.shared
        if CommandLine.arguments.contains("--qa-use-mock-data") {
            monitor.prepareQAPreview()
        } else {
            monitor.start()
        }
        if CommandLine.arguments.contains("--qa-register-shortcut") {
            ShortcutSettings.shared.activate()
        } else {
            ShortcutSettings.shared.prepareQAPreview()
        }

        guard let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main else { return }
        let size = NSSize(width: 680, height: 460)
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - size.width - 24,
            y: screen.visibleFrame.maxY - size.height - 18
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: MenuPopoverView(monitor: monitor))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        qaPanel = panel

        if CommandLine.arguments.contains("--qa-complete-first") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                if let first = monitor.reminders.first {
                    monitor.complete(first)
                }
            }
        }

        if CommandLine.arguments.contains("--qa-move-overdue-first") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                if let first = monitor.overdueReminders.first {
                    monitor.moveToToday(first)
                }
            }
        }

        if CommandLine.arguments.contains("--qa-record-shortcut") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                ShortcutSettings.shared.startRecording()
            }
        }

        if !CommandLine.arguments.contains("--qa-no-flight") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                FlightOverlayController.shared.show(reminders: monitor.reminders)
            }
        }
    }
}

@main
struct FlightReminderApp: App {
    @NSApplicationDelegateAdaptor(FlightReminderAppDelegate.self) private var appDelegate
    @StateObject private var monitor = ReminderMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPopoverView(monitor: monitor)
        } label: {
            Image(systemName: monitor.reminders.isEmpty ? "airplane" : "airplane.circle.fill")
                .accessibilityLabel("清风航线")
        }
        .menuBarExtraStyle(.window)
    }
}
