import ActivityKit
import Foundation

@MainActor
final class InsulinActivityManager {
    static let shared = InsulinActivityManager()

    private init() {}

    func refresh(store: DoseStore, now: Date = Date()) async {
        let schedule = DoseSchedule.make(entries: store.entries, now: now)

        for period in InsulinPeriod.allCases {
            let isLate = schedule.isOverdue && schedule.nextPeriod == period

            if isLate {
                await startOverdueActivity(for: period, now: now)
            } else {
                await dismissActivity(for: period)
            }
        }
    }

    func startOverdueActivity(for period: InsulinPeriod, now: Date = Date()) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activities(for: period).isEmpty else { return }

        let end = Calendar.current.date(byAdding: .hour, value: 4, to: now) ?? now.addingTimeInterval(14_400)
        let attributes = InsulinActivityAttributes(periodID: period.rawValue, dogName: "Isis")
        let state = InsulinActivityAttributes.ContentState(
            periodTitle: period.title,
            countdownEndsAt: end,
            isOverdue: true
        )
        let content = ActivityContent(state: state, staleDate: end)

        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            print("Unable to start Insulisis Live Activity: \(error.localizedDescription)")
        }
    }

    func dismissActivity(for period: InsulinPeriod) async {
        for activity in activities(for: period) {
            let state = InsulinActivityAttributes.ContentState(
                periodTitle: period.title,
                countdownEndsAt: Date(),
                isOverdue: false
            )
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    private func activities(for period: InsulinPeriod) -> [Activity<InsulinActivityAttributes>] {
        Activity<InsulinActivityAttributes>.activities.filter {
            $0.attributes.periodID == period.rawValue
        }
    }
}
