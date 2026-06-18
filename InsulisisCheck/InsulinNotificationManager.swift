import Foundation
import UserNotifications

final class InsulinNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = InsulinNotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let notificationPrefix = "insulisis-dose-reminder"
    private let overdueOffsets: [Int] = [15, 30, 60]

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
    }

    func refresh(entries: [DoseEntry]) async {
        await requestAuthorizationIfNeeded()

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            await cancelScheduledNotifications()
            return
        }

        await cancelScheduledNotifications()

        let schedule = DoseSchedule.make(entries: entries)
        await scheduleDoseNotification(for: schedule)
        await scheduleOverdueNotifications(for: schedule)
    }

    func cancelScheduledNotifications() async {
        let pendingRequests = await center.pendingNotificationRequests()
        let identifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(notificationPrefix) }

        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    private func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }

        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func scheduleDoseNotification(for schedule: DoseSchedule) async {
        await scheduleNotification(
            identifier: notificationIdentifier(for: schedule, suffix: "due"),
            title: "Hora da insulina da \(schedule.nextPeriod.title.lowercased())",
            body: "Está na hora de aplicar a insulina da Isis.",
            date: schedule.nextDoseDate,
            interruptionLevel: .timeSensitive
        )
    }

    private func scheduleOverdueNotifications(for schedule: DoseSchedule) async {
        for offset in overdueOffsets {
            guard let date = Calendar.current.date(byAdding: .minute, value: offset, to: schedule.nextDoseDate) else {
                continue
            }

            await scheduleNotification(
                identifier: notificationIdentifier(for: schedule, suffix: "overdue-\(offset)"),
                title: "A insulina da \(schedule.nextPeriod.title.lowercased()) já foi aplicada?",
                body: "Já passaram \(offset) minutos do horário previsto da Isis. Confere se ficou tudo certo?",
                date: date,
                interruptionLevel: .timeSensitive
            )
        }
    }

    private func scheduleNotification(
        identifier: String,
        title: String,
        body: String,
        date: Date,
        interruptionLevel: UNNotificationInterruptionLevel
    ) async {
        guard date > Date.now else { return }

        var dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        dateComponents.second = 0

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = interruptionLevel

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try? await center.add(request)
    }

    private func notificationIdentifier(for schedule: DoseSchedule, suffix: String) -> String {
        let dateText = ISO8601DateFormatter().string(from: schedule.nextDoseDate)
        return "\(notificationPrefix)-\(schedule.nextPeriod.rawValue)-\(dateText)-\(suffix)"
    }
}
