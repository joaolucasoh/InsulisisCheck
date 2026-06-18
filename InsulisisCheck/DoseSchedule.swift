import Foundation

struct DoseSchedule: Equatable {
    static let overdueGracePeriod: TimeInterval = 15 * 60

    let nextPeriod: InsulinPeriod
    let nextDoseDate: Date

    var isOverdue: Bool {
        isOverdue(at: Date.now)
    }

    var isDue: Bool {
        isDue(at: Date.now)
    }

    func isDue(at date: Date) -> Bool {
        date >= nextDoseDate && !isOverdue(at: date)
    }

    func isOverdue(at date: Date) -> Bool {
        date >= nextDoseDate.addingTimeInterval(Self.overdueGracePeriod)
    }

    var nextDoseText: String {
        nextDoseDate.insulisisShortDayTimeText
    }

    static func make(entries: [DoseEntry], now: Date = Date(), calendar: Calendar = .current) -> DoseSchedule {
        if let latestEntry = entries.max(by: { $0.date < $1.date }) {
            let nextDate = calendar.date(byAdding: .hour, value: 12, to: latestEntry.date) ?? latestEntry.date.addingTimeInterval(43_200)
            return DoseSchedule(nextPeriod: latestEntry.period.next, nextDoseDate: nextDate)
        }

        let morning = InsulinPeriod.morning.deadline(on: now, calendar: calendar)
        if now < morning {
            return DoseSchedule(nextPeriod: .morning, nextDoseDate: morning)
        }

        let night = InsulinPeriod.night.deadline(on: now, calendar: calendar)
        if now < night {
            return DoseSchedule(nextPeriod: .night, nextDoseDate: night)
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        return DoseSchedule(nextPeriod: .morning, nextDoseDate: InsulinPeriod.morning.deadline(on: tomorrow, calendar: calendar))
    }
}
