import AppKit
import SwiftUI

@MainActor
final class FlightOverlayController {
    static let shared = FlightOverlayController()

    private var panels: [NSPanel] = []
    private var animators: [FlightAnimator] = []

    func show(reminders: [ReminderItem], isTest: Bool = false) {
        closeAll()

        let targets = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens
        panels = targets.map { screen in
            let size = NSSize(width: 980, height: 190)
            let start = NSPoint(
                x: screen.frame.minX - size.width - 40,
                y: screen.frame.maxY - 320
            )
            let panel = NSPanel(
                contentRect: NSRect(origin: start, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            panel.hidesOnDeactivate = false
            let animator = FlightAnimator(
                startX: start.x,
                endX: screen.frame.maxX + 40,
                y: start.y,
                duration: 10.0
            )
            let hoverState = FlightHoverState()
            let hostingView = HoverHostingView(
                rootView: FlightBannerView(
                    reminders: reminders,
                    isTest: isTest,
                    hoverState: hoverState,
                    onFinished: { [weak panel, weak animator] in
                        animator?.stop()
                        panel?.orderOut(nil)
                    }
                )
            )
            hostingView.onHoverChanged = { [weak animator, weak hoverState] hovering in
                hoverState?.isHovered = hovering
                animator?.setPaused(hovering)
            }
            panel.contentView = hostingView
            panel.orderFrontRegardless()
            animator.start(panel: panel)
            animators.append(animator)
            return panel
        }
    }

    func closeAll() {
        animators.forEach { $0.stop() }
        animators.removeAll()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}

@MainActor
private final class FlightHoverState: ObservableObject {
    @Published var isHovered = false
}

@MainActor
private final class HoverHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}

@MainActor
private final class FlightAnimator {
    private weak var panel: NSPanel?
    private let startX: CGFloat
    private let endX: CGFloat
    private let y: CGFloat
    private let duration: TimeInterval

    private var timer: Timer?
    private var progress = 0.0
    private var lastTick = Date()
    private var isPaused = false

    init(startX: CGFloat, endX: CGFloat, y: CGFloat, duration: TimeInterval) {
        self.startX = startX
        self.endX = endX
        self.y = y
        self.duration = duration
    }

    func start(panel: NSPanel) {
        self.panel = panel
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        lastTick = Date()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let panel else {
            stop()
            return
        }

        let now = Date()
        let delta = min(now.timeIntervalSince(lastTick), 0.1)
        lastTick = now
        guard !isPaused else { return }

        progress = min(1, progress + delta / duration)
        let x = startX + (endX - startX) * progress
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        if progress >= 1 {
            stop()
            panel.orderOut(nil)
        }
    }
}

private struct FlightBannerView: View {
    let reminders: [ReminderItem]
    let isTest: Bool
    @ObservedObject var hoverState: FlightHoverState
    let onFinished: () -> Void

    private static let planeImage: NSImage? = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("plane.png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    private var heading: String {
        if isTest {
            return reminders.isEmpty ? "测试飞行 · 今天没有提醒" : "测试飞行 · 今天 \(reminders.count) 项"
        }
        return "今天还有 \(reminders.count) 项提醒"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 2) {
            banner

            if let plane = Self.planeImage {
                AnimatedPlaneView(image: plane)
            } else {
                Image(systemName: "airplane")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 110, height: 90)
            }
        }
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var banner: some View {
        Button(action: openReminders) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Text(heading)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if reminders.count > 3 {
                        Text("+\(reminders.count - 3)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.10), in: Capsule())
                    }

                    if hoverState.isHovered {
                        Label("已暂停", systemImage: "pause.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Text("打开提醒事项")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                }

                if reminders.isEmpty {
                    Text("当前没有可展示的真实提醒数据")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(Array(reminders.prefix(3).enumerated()), id: \.element.id) { _, reminder in
                            HStack(alignment: .top, spacing: 7) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 4)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminder.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(reminder.dueDate.map { "今天 \(Self.timeFormatter.string(from: $0))" } ?? reminder.listTitle)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 140, alignment: .leading)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: 590, alignment: .leading)
            .padding(.horizontal, 23)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.accentColor.opacity(0.04))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.78), lineWidth: 1)
            }
            .shadow(color: Color.accentColor.opacity(0.10), radius: 28, y: 10)
            .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isTest ? "测试飞行，展示今天的真实提醒数据" : "打开提醒事项，今天还有 \(reminders.count) 项未完成")
    }

    private func openReminders() {
        let url = URL(fileURLWithPath: "/System/Applications/Reminders.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        onFinished()
    }
}

private struct AnimatedPlaneView: View {
    let image: NSImage

    @State private var propellerSpinning = false

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 178, height: 108)
                .offset(x: -7)
                .shadow(color: .blue.opacity(0.18), radius: 12, y: 6)

            Image(systemName: "fanblades.fill")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(.white.opacity(0.88))
                .shadow(color: .blue.opacity(0.45), radius: 5)
                .rotationEffect(.degrees(propellerSpinning ? 360 : 0))
                .offset(x: 85, y: -1)
                .animation(
                    .linear(duration: 0.16).repeatForever(autoreverses: false),
                    value: propellerSpinning
                )
        }
        .frame(width: 200, height: 112)
        .onAppear { propellerSpinning = true }
        .accessibilityHidden(true)
    }
}
