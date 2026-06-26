import AppKit
import EventKit
import SwiftUI

struct MenuPopoverView: View {
    @ObservedObject var monitor: ReminderMonitor
    @ObservedObject private var shortcutSettings = ShortcutSettings.shared

    @AppStorage("monitorEnabled") private var monitorEnabled = true
    @AppStorage("checkIntervalMinutes") private var checkIntervalMinutes = 30
    @AppStorage("quietStartMinutes") private var quietStartMinutes = 22 * 60 + 30
    @AppStorage("quietEndMinutes") private var quietEndMinutes = 7 * 60 + 30
    @AppStorage("soundEnabled") private var soundEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    @State private var animateGlow = false
    @State private var iconHovered = false
    @State private var testFlightHovered = false
    @State private var pulseGreen = 0.6
    @State private var planeOffset: CGFloat = -20
    @State private var showAbout = false
    @State private var showCompleteAllConfirm = false
    @State private var toastMessage: String?
    @State private var toastIsError = true

    @Environment(\.colorScheme) private var colorScheme

    private static let appIcon: NSImage? = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns") else { return nil }
        return NSImage(contentsOf: url)
    }()

    // MARK: - Adaptive Colors
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.42)
    }
    private var pillBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.4)
    }
    private var subtleBorder: Color {
        Color.primary.opacity(0.08)
    }
    private var gradientColors: [Color] {
        colorScheme == .dark
            ? [Color(red: 0.12, green: 0.10, blue: 0.18),
               Color(red: 0.10, green: 0.12, blue: 0.20),
               Color(red: 0.18, green: 0.10, blue: 0.14)]
            : [Color(red: 0.94, green: 0.91, blue: 0.98),
               Color(red: 0.90, green: 0.93, blue: 0.99),
               Color(red: 0.98, green: 0.92, blue: 0.94)]
    }

    var body: some View {
        ZStack {
            mainContent

            // Error / success toast overlay
            if let message = toastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: toastIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(toastIsError ? Color.orange : Color.green)
                        Text(message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: Color.black.opacity(0.1), radius: 8, y: 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 50)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastMessage)
            }

            // Onboarding overlay
            if !hasCompletedOnboarding {
                onboardingOverlay
            }
        }
        .onChange(of: monitor.lastError) { _, newValue in
            if let error = newValue {
                showToast(error, isError: true)
            }
        }
        .onChange(of: shortcutSettings.errorMessage) { _, newValue in
            if let error = newValue {
                showToast(error, isError: true)
            }
        }
        .sheet(isPresented: $showAbout) {
            aboutSheet
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Simulated Traffic Lights Row
            HStack {
                HStack(spacing: 6) {
                    // Red: functional close
                    Circle()
                        .fill(Color(red: 1.0, green: 0.37, blue: 0.34))
                        .frame(width: 12, height: 12)
                        .onTapGesture {
                            NSApp.sendAction(Selector(("dismissPopover:")), to: nil, from: nil)
                        }
                        .help("关闭面板")
                    Circle()
                        .fill(Color(red: 1.0, green: 0.74, blue: 0.18))
                        .frame(width: 12, height: 12)
                    Circle()
                        .fill(Color(red: 0.15, green: 0.79, blue: 0.25))
                        .frame(width: 12, height: 12)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            // Header Section
            HStack(spacing: 12) {
                Group {
                    if let icon = Self.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "airplane")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.blue)
                    }
                }
                .frame(width: 44, height: 44)
                .cornerRadius(10)
                .scaleEffect(iconHovered ? 1.08 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: iconHovered)
                .onHover { hover in
                    iconHovered = hover
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("清风航线")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.1, green: 0.5, blue: 1.0), Color(red: 0.85, green: 0.25, blue: 0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    HStack(spacing: 5) {
                        if monitor.isQuietTimeNow {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.orange)
                            Text("勿扰模式生效中")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.orange)
                        } else {
                            Circle()
                                .fill(monitorEnabled ? Color(red: 0.15, green: 0.79, blue: 0.25) : Color.secondary)
                                .frame(width: 6, height: 6)
                                .shadow(color: monitorEnabled ? Color(red: 0.15, green: 0.79, blue: 0.25).opacity(0.8) : Color.clear, radius: 2)
                                .opacity(monitorEnabled ? pulseGreen : 1.0)
                            Text(monitorEnabled ? "提醒飞行已启用" : "提醒飞行已暂停")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Toggle("", isOn: $monitorEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Today's summary & refresh row
            HStack {
                Text(monitor.reminders.isEmpty ? "今天没有待处理提醒" : "今天还有 \(monitor.reminders.count) 项提醒")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if monitor.isChecking {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        monitor.refresh(shouldFly: false)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Reminders card list container
            VStack(spacing: 0) {
                if !monitor.isAuthorized {
                    permissionCard
                } else if monitor.reminders.isEmpty && monitor.overdueReminders.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("今天的航线很清爽")
                                .font(.system(size: 12, weight: .semibold))
                            Text("清风航线会继续安静巡航")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                } else {
                    let items = monitor.reminders + monitor.overdueReminders
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 {
                                    Divider()
                                }
                                ReminderRow(
                                    item: item,
                                    isOverdue: monitor.overdueReminders.contains(where: { $0.id == item.id }),
                                    isCompleting: monitor.completingReminderIDs.contains(item.id),
                                    isRescheduling: monitor.reschedulingReminderIDs.contains(item.id),
                                    onMoveToToday: monitor.overdueReminders.contains(where: { $0.id == item.id }) ? { monitor.moveToToday(item) } : nil,
                                    onComplete: { monitor.complete(item) }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
                
                Divider()
                
                HStack {
                    Button {
                        monitor.openReminders()
                    } label: {
                        HStack {
                            Text("打开提醒事项")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.blue)

                    if (monitor.reminders.count + monitor.overdueReminders.count) >= 2 {
                        Divider().frame(height: 16)

                        Button {
                            showCompleteAllConfirm = true
                        } label: {
                            Text("全部完成")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog("确认完成所有提醒？", isPresented: $showCompleteAllConfirm, titleVisibility: .visible) {
                            Button("全部完成", role: .destructive) {
                                monitor.completeAll()
                            }
                            Button("取消", role: .cancel) {}
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(cardBackground)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)

            // Settings section
            VStack(spacing: 8) {
                // Row 1: 检测间隔
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("检测间隔")
                        .font(.system(size: 12, weight: .semibold))
                    Text(nextFlightText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                    Spacer()
                    
                    Menu {
                        ForEach([5, 15, 30, 60, 120], id: \.self) { mins in
                            Button(intervalText(mins)) {
                                checkIntervalMinutes = mins
                                monitor.restartSchedule()
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(intervalText(checkIntervalMinutes))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.blue)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(pillBackground)
                        .cornerRadius(6)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(subtleBorder, lineWidth: 1)
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                }
                
                Divider()
                
                // Row 2: 勿扰时段
                HStack(spacing: 8) {
                    Image(systemName: "moon")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("勿扰时段")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    
                    HStack(spacing: 4) {
                        TimeDropdownPicker(totalMinutes: $quietStartMinutes, pillBackground: pillBackground, subtleBorder: subtleBorder)
                        Text("–")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TimeDropdownPicker(totalMinutes: $quietEndMinutes, pillBackground: pillBackground, subtleBorder: subtleBorder)
                    }
                }
                
                Divider()

                // Row 3: 声音提醒
                HStack(spacing: 8) {
                    Image(systemName: soundEnabled ? "speaker.wave.2" : "speaker.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("声音提醒")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Toggle("", isOn: $soundEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }

                Divider()
                
                // Row 4: 关于清风航线
                Button(action: { showAbout = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text("关于清风航线")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Footer Section
            HStack(spacing: 8) {
                Button {
                    monitor.testFlight()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                            .offset(x: testFlightHovered ? 3 : 0, y: testFlightHovered ? -3 : 0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: testFlightHovered)
                        Text("测试飞行")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.85, green: 0.25, blue: 0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(8)
                    .shadow(color: Color(red: 0.85, green: 0.25, blue: 0.9).opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .onHover { hover in
                    testFlightHovered = hover
                }
                
                // Shortcut button with recording animation
                Button {
                    shortcutSettings.startRecording()
                } label: {
                    VStack(spacing: 1) {
                        HStack(spacing: 5) {
                            Image(systemName: shortcutSettings.isRecording ? "record.circle" : "keyboard")
                                .font(.system(size: 11))
                            Text(shortcutSettings.displayText)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundStyle(shortcutSettings.isRecording ? Color.orange : Color.primary.opacity(0.72))

                        if shortcutSettings.isRecording {
                            Text("Esc 取消 · Delete 清除")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(pillBackground)
                    .cornerRadius(8)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(shortcutSettings.isRecording ? Color.orange.opacity(0.5) : subtleBorder, lineWidth: 1)
                    }
                    .opacity(shortcutSettings.isRecording ? (pulseGreen > 0.8 ? 0.7 : 1.0) : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: shortcutSettings.isRecording)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Last checked & Exit
            HStack {
                if let lastChecked = monitor.lastChecked {
                    Text("上次检测于 \(lastChecked, style: .relative)前")
                } else {
                    Text("等待首次检测")
                }
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.secondary)
                    .font(.system(size: 10))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(width: 680)
        .background {
            ZStack {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                Circle()
                    .fill(Color(red: 0.35, green: 0.65, blue: 1.0).opacity(colorScheme == .dark ? 0.12 : 0.24))
                    .frame(width: 480, height: 480)
                    .blur(radius: 70)
                    .offset(x: animateGlow ? 200 : -200, y: animateGlow ? -100 : 100)
                
                Circle()
                    .fill(Color(red: 0.95, green: 0.4, blue: 0.85).opacity(colorScheme == .dark ? 0.10 : 0.18))
                    .frame(width: 400, height: 400)
                    .blur(radius: 60)
                    .offset(x: animateGlow ? -180 : 180, y: animateGlow ? 100 : -100)
                
                Circle()
                    .fill(Color(red: 1.0, green: 0.6, blue: 0.4).opacity(colorScheme == .dark ? 0.06 : 0.12))
                    .frame(width: 320, height: 320)
                    .blur(radius: 50)
                    .offset(x: animateGlow ? 100 : -100, y: animateGlow ? 120 : -120)
            }
            .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: animateGlow)
        }
        .background(.ultraThinMaterial)
        .tint(Color.blue)
        .onAppear {
            animateGlow = true
            monitor.start()
            shortcutSettings.activate()
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseGreen = 1.0
            }
        }
        .onDisappear {
            shortcutSettings.cancelRecording()
        }
    }

    // MARK: - Onboarding Overlay
    private var onboardingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                if let icon = Self.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .cornerRadius(16)
                }

                Text("欢迎使用清风航线")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.1, green: 0.5, blue: 1.0), Color(red: 0.85, green: 0.25, blue: 0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                VStack(alignment: .leading, spacing: 12) {
                    Label("当今天还有未完成的提醒事项时", systemImage: "bell.badge")
                    Label("一架飞机会拖着横幅飞过屏幕提醒你", systemImage: "airplane")
                    Label("需要读取「提醒事项」才能工作", systemImage: "lock.shield")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

                Button {
                    withAnimation(.spring(response: 0.4)) {
                        hasCompletedOnboarding = true
                    }
                } label: {
                    Text("开始使用")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 180, height: 36)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.85, green: 0.25, blue: 0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding(32)
            .frame(width: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 30, y: 10)
        }
        .transition(.opacity)
    }

    // MARK: - About Sheet
    private var aboutSheet: some View {
        VStack(spacing: 16) {
            if let icon = Self.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .cornerRadius(14)
            }

            Text("清风航线")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.1, green: 0.5, blue: 1.0), Color(red: 0.85, green: 0.25, blue: 0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            if !version.isEmpty {
                Text("版本 \(version)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text("当今天还有未完成的提醒事项时，\n让一架飞机拖着横幅飞过屏幕。")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 4) {
                Text("数据完全保留在本机")
                    .font(.system(size: 11, weight: .medium))
                Text("不上传到任何服务器")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button("好") {
                showAbout = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(28)
        .frame(width: 320)
    }

    // MARK: - Helpers
    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(monitor.authorizationMessage, systemImage: "lock.shield")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(monitor.authorizationStatus == .notDetermined ? "允许访问提醒事项" : "打开隐私设置") {
                if monitor.authorizationStatus == .notDetermined {
                    monitor.requestAccess()
                } else {
                    monitor.openPrivacySettings()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func intervalText(_ minutes: Int) -> String {
        if minutes >= 120 {
            return "\(minutes / 60) 小时"
        } else if minutes >= 60 {
            return "60 分钟"
        } else {
            return "\(minutes) 分钟"
        }
    }

    private var nextFlightText: String {
        guard monitorEnabled else { return "已暂停" }
        guard let next = monitor.nextScheduledCheckAt else { return "下次飞行时间：待定" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return "下次飞行时间：\(formatter.string(from: next))"
    }

    private func showToast(_ message: String, isError: Bool) {
        withAnimation {
            toastMessage = message
            toastIsError = isError
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                if toastMessage == message {
                    toastMessage = nil
                }
            }
        }
    }
}

// MARK: - Custom Time Pickers
struct TimeDropdownPicker: View {
    @Binding var totalMinutes: Int
    var pillBackground: Color = Color.white.opacity(0.4)
    var subtleBorder: Color = Color.primary.opacity(0.08)
    
    var body: some View {
        HStack(spacing: 3) {
            Menu {
                ForEach(0..<24, id: \.self) { h in
                    Button(String(format: "%02d", h)) {
                        let currentMin = totalMinutes % 60
                        totalMinutes = h * 60 + currentMin
                    }
                }
            } label: {
                Text(String(format: "%02d", totalMinutes / 60))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            
            Text(":")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            
            Menu {
                ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { m in
                    Button(String(format: "%02d", m)) {
                        let currentHour = totalMinutes / 60
                        totalMinutes = currentHour * 60 + m
                    }
                }
            } label: {
                Text(String(format: "%02d", totalMinutes % 60))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8))
                .foregroundStyle(Color.purple)
                .padding(.leading, 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(pillBackground)
        .cornerRadius(6)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(subtleBorder, lineWidth: 1)
        }
    }
}

// MARK: - Custom Reminder Row with Animation
private struct ReminderRow: View {
    let item: ReminderItem
    let isOverdue: Bool
    let isCompleting: Bool
    let isRescheduling: Bool
    let onMoveToToday: (() -> Void)?
    let onComplete: () -> Void

    @State private var isHovered = false
    @State private var didComplete = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let overdueFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(isOverdue ? Color.orange : Color.blue)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .strikethrough(didComplete, color: .secondary)
                
                HStack(spacing: 4) {
                    if isOverdue {
                        Text(item.dueDate.map { "已过期 · \(Self.overdueFormatter.string(from: $0))" } ?? "已过期")
                            .foregroundStyle(.orange)
                    } else {
                        Text(item.dueDate.map { "今天 \(Self.timeFormatter.string(from: $0))" } ?? "今天")
                    }
                    Text("·")
                    Text(item.listTitle)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            if let onMoveToToday {
                Button(action: onMoveToToday) {
                    if isRescheduling {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 32)
                    } else {
                        Text("今天办")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.10), in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRescheduling || isCompleting)
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    didComplete = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    onComplete()
                }
            } label: {
                Group {
                    if isCompleting || didComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 16, weight: .regular))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isCompleting || isRescheduling || didComplete)
            .animation(.spring(response: 0.3), value: didComplete)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hover
            }
        }
    }
}
