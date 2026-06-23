import AppKit
import EventKit
import SwiftUI

struct MenuPopoverView: View {
    @ObservedObject var monitor: ReminderMonitor

    @AppStorage("monitorEnabled") private var monitorEnabled = true
    @AppStorage("checkIntervalMinutes") private var checkIntervalMinutes = 30
    @AppStorage("quietStartMinutes") private var quietStartMinutes = 22 * 60 + 30
    @AppStorage("quietEndMinutes") private var quietEndMinutes = 7 * 60 + 30

    private static let appIcon: NSImage? = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        VStack(spacing: 0) {
            header

            if !monitor.isAuthorized {
                permissionCard
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }

            remindersSection
                .padding(.horizontal, 14)

            settingsSection
                .padding(.horizontal, 14)
                .padding(.top, 12)

            footer
        }
        .frame(width: 400)
        .background(.ultraThinMaterial)
        .tint(Color.accentColor)
        .onAppear { monitor.start() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = Self.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "airplane")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 38, height: 38)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("清风航线")
                    .font(.system(size: 16, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(monitorEnabled ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(monitorEnabled ? "提醒飞行已启用" : "提醒飞行已暂停")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("启用提醒飞行", isOn: $monitorEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(monitor.authorizationMessage, systemImage: "lock.shield")
                .font(.system(size: 12, weight: .medium))
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
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(monitor.reminders.isEmpty ? "今天没有待处理提醒" : "今天还有 \(monitor.reminders.count) 项提醒")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                if !monitor.overdueReminders.isEmpty {
                    Text("已过期 \(monitor.overdueReminders.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.11), in: Capsule())
                }

                Spacer()

                if monitor.isChecking {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        monitor.refresh(shouldFly: false)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("立即刷新")
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                if monitor.isAuthorized && monitor.reminders.isEmpty && monitor.overdueReminders.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 25))
                            .foregroundStyle(Color.green)
                        Text("今天的航线很清爽")
                            .font(.system(size: 13, weight: .semibold))
                        Text("清风航线会继续安静巡航")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(Array(monitor.reminders.prefix(4).enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().padding(.leading, 40)
                        }
                        ReminderRow(
                            item: item,
                            isOverdue: false,
                            isCompleting: monitor.completingReminderIDs.contains(item.id),
                            isRescheduling: false,
                            onMoveToToday: nil,
                            onComplete: { monitor.complete(item) }
                        )
                    }
                }

                if !monitor.overdueReminders.isEmpty {
                    if !monitor.reminders.isEmpty {
                        Divider().padding(.leading, 40)
                    }

                    HStack(spacing: 7) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text("已过期 \(monitor.overdueReminders.count) 项")
                    }
                    .foregroundStyle(.orange)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 13)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                    ForEach(Array(monitor.overdueReminders.prefix(4).enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().padding(.leading, 40)
                        }
                        ReminderRow(
                            item: item,
                            isOverdue: true,
                            isCompleting: monitor.completingReminderIDs.contains(item.id),
                            isRescheduling: monitor.reschedulingReminderIDs.contains(item.id),
                            onMoveToToday: { monitor.moveToToday(item) },
                            onComplete: { monitor.complete(item) }
                        )
                    }
                }

                if monitor.isAuthorized {
                    Divider().padding(.leading, 40)
                    Button {
                        monitor.openReminders()
                    } label: {
                        HStack {
                            Text("打开提醒事项")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(Color.accentColor.opacity(0.055))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
            }
        }
    }

    private var settingsSection: some View {
        VStack(spacing: 0) {
            settingRow(icon: "clock", title: "检测间隔") {
                Picker("检测间隔", selection: $checkIntervalMinutes) {
                    Text("5 分钟").tag(5)
                    Text("15 分钟").tag(15)
                    Text("30 分钟").tag(30)
                    Text("60 分钟").tag(60)
                    Text("2 小时").tag(120)
                }
                .labelsHidden()
                .frame(width: 96)
                .onChange(of: checkIntervalMinutes) { _, _ in monitor.restartSchedule() }
            }

            Divider().padding(.leading, 43)

            settingRow(icon: "moon", title: "勿扰时段") {
                HStack(spacing: 4) {
                    compactTimePicker(minutes: $quietStartMinutes)
                    Text("–").foregroundStyle(.tertiary)
                    compactTimePicker(minutes: $quietEndMinutes)
                }
            }

            Divider().padding(.leading, 43)

            Button(action: showAbout) {
                HStack(spacing: 11) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("关于清风航线")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 0.7)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let error = monitor.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                monitor.testFlight()
            } label: {
                Label("测试飞行", systemImage: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack {
                if let lastChecked = monitor.lastChecked {
                    Text("上次检测于 \(lastChecked, style: .relative)前")
                } else {
                    Text("等待首次检测")
                }
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
        }
        .padding(14)
    }

    private func settingRow<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func compactTimePicker(minutes: Binding<Int>) -> some View {
        let value = Binding<Date>(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
        return DatePicker("时间", selection: value, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.field)
            .environment(\.locale, Locale(identifier: "en_GB"))
            .frame(width: 72)
    }

    private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "清风航线"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        alert.informativeText = "当今天还有未完成的提醒事项时，让一架飞机拖着横幅飞过屏幕。\n\n版本 \(version)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

private struct ReminderRow: View {
    let item: ReminderItem
    let isOverdue: Bool
    let isCompleting: Bool
    let isRescheduling: Bool
    let onMoveToToday: (() -> Void)?
    let onComplete: () -> Void

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
        HStack(alignment: .center, spacing: 11) {
            Circle()
                .fill(isOverdue ? Color.orange : Color.accentColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
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

            Spacer()

            if let onMoveToToday {
                Button(action: onMoveToToday) {
                    if isRescheduling {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 34)
                    } else {
                        Text("今天办")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(Color.accentColor)
                .disabled(isRescheduling || isCompleting)
                .help("把截止日期改为今天")
            }

            Button(action: onComplete) {
                Group {
                    if isCompleting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "circle")
                            .font(.system(size: 16, weight: .regular))
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .disabled(isCompleting || isRescheduling)
            .help("标记为已完成")
            .accessibilityLabel("完成提醒：\(item.title)")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }
}
