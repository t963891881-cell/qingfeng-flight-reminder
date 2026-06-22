import AppKit
import EventKit
import Foundation

@MainActor
final class ReminderMonitor: ObservableObject {
    static let shared = ReminderMonitor()

    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var completingReminderIDs: Set<String> = []
    @Published var lastError: String?

    private let store = EKEventStore()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastFlightAt: Date?
    private var hasStarted = false
    private var isQAPreview = false

    private init() {
        UserDefaults.standard.register(defaults: [
            "monitorEnabled": true,
            "checkIntervalMinutes": 30,
            "quietStartMinutes": 22 * 60 + 30,
            "quietEndMinutes": 7 * 60 + 30
        ])
    }

    var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    var authorizationMessage: String {
        switch authorizationStatus {
        case .notDetermined: return "需要读取提醒事项，才能发现今天未完成的任务。"
        case .denied, .restricted: return "提醒事项权限已关闭，请到系统设置中开启。"
        case .writeOnly: return "当前只有写入权限，需要完整访问权限。"
        default: return "已连接系统提醒事项"
        }
    }

    func start() {
        guard !isQAPreview else { return }
        guard !hasStarted else { return }
        hasStarted = true

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: store,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh(shouldFly: false) }
            }
        )
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.restartSchedule()
                    self?.refresh(shouldFly: true)
                }
            }
        )

        if authorizationStatus == .notDetermined {
            requestAccess()
        } else {
            refresh(shouldFly: true)
        }
        restartSchedule()
    }

    func requestAccess() {
        Task {
            do {
                let granted = try await store.requestFullAccessToReminders()
                authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
                lastError = granted ? nil : "没有获得提醒事项访问权限。"
                if granted { refresh(shouldFly: true) }
            } catch {
                authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
                lastError = error.localizedDescription
            }
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") else { return }
        NSWorkspace.shared.open(url)
    }

    func openReminders() {
        let url = URL(fileURLWithPath: "/System/Applications/Reminders.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func restartSchedule() {
        timer?.invalidate()
        let minutes = max(5, UserDefaults.standard.integer(forKey: "checkIntervalMinutes"))
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(shouldFly: true) }
        }
    }

    func refresh(shouldFly: Bool, showTestAfterRefresh: Bool = false) {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        guard isAuthorized else {
            reminders = []
            return
        }

        isChecking = true
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? Date().addingTimeInterval(86_400)
        // EventKit calendars can carry a different or missing time zone. Query a
        // slightly wider window, then enforce the exact local calendar day below.
        let queryStart = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let queryEnd = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: queryStart,
            ending: queryEnd,
            calendars: nil
        )

        store.fetchReminders(matching: predicate) { [weak self] fetched in
            let items = (fetched ?? []).compactMap { reminder -> ReminderItem? in
                guard let dueDate = Self.localDueDate(for: reminder, calendar: calendar) else {
                    return nil
                }
                guard calendar.isDate(dueDate, inSameDayAs: now) else {
                    return nil
                }

                return ReminderItem(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? reminder.title! : "未命名提醒",
                    dueDate: dueDate,
                    listTitle: reminder.calendar.title
                )
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

            DispatchQueue.main.async {
                guard let self else { return }
                self.reminders = items
                self.isChecking = false
                self.lastChecked = Date()
                self.lastError = nil

                if showTestAfterRefresh {
                    FlightOverlayController.shared.show(reminders: items, isTest: true)
                    return
                }

                if shouldFly,
                   !items.isEmpty,
                   UserDefaults.standard.object(forKey: "monitorEnabled") as? Bool ?? true,
                   !self.isQuietTime,
                   self.canFlyNow {
                    self.lastFlightAt = Date()
                    FlightOverlayController.shared.show(reminders: items)
                }
            }
        }
    }

    func testFlight() {
        refresh(shouldFly: false, showTestAfterRefresh: true)
    }

    func complete(_ item: ReminderItem) {
        guard !completingReminderIDs.contains(item.id) else { return }

        if isQAPreview {
            reminders.removeAll { $0.id == item.id }
            return
        }

        guard isAuthorized else {
            lastError = "没有提醒事项完整访问权限。"
            return
        }
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else {
            lastError = "找不到这条提醒事项，请刷新后重试。"
            refresh(shouldFly: false)
            return
        }

        completingReminderIDs.insert(item.id)
        reminder.isCompleted = true
        reminder.completionDate = Date()

        do {
            try store.save(reminder, commit: true)
            reminders.removeAll { $0.id == item.id }
            lastError = nil
            completingReminderIDs.remove(item.id)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.refresh(shouldFly: false)
            }
        } catch {
            completingReminderIDs.remove(item.id)
            lastError = "无法完成提醒：\(error.localizedDescription)"
        }
    }

    func prepareQAPreview() {
        isQAPreview = true
        authorizationStatus = .fullAccess
        reminders = [
            ReminderItem(id: "qa-1", title: "提交报价单", dueDate: Date(), listTitle: "工作"),
            ReminderItem(id: "qa-2", title: "准备周会资料", dueDate: Date().addingTimeInterval(3600), listTitle: "工作"),
            ReminderItem(id: "qa-3", title: "跟进客户反馈", dueDate: Date().addingTimeInterval(7200), listTitle: "提醒")
        ]
        lastChecked = Date()
    }

    private var canFlyNow: Bool {
        guard let lastFlightAt else { return true }
        return Date().timeIntervalSince(lastFlightAt) > 30
    }

    nonisolated private static func localDueDate(for reminder: EKReminder, calendar: Calendar) -> Date? {
        guard var components = reminder.dueDateComponents else { return nil }
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return calendar.date(from: components)
    }

    private var isQuietTime: Bool {
        let defaults = UserDefaults.standard
        let start = defaults.object(forKey: "quietStartMinutes") as? Int ?? 22 * 60 + 30
        let end = defaults.object(forKey: "quietEndMinutes") as? Int ?? 7 * 60 + 30
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let current = (now.hour ?? 0) * 60 + (now.minute ?? 0)

        if start == end { return false }
        return start < end ? (current >= start && current < end) : (current >= start || current < end)
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
