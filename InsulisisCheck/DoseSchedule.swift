import Foundation

struct DoseSchedule: Equatable {
    let nextPeriod: InsulinPeriod
    let nextDoseDate: Date

    var isOverdue: Bool {
        Date.now >= nextDoseDate
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
