import Foundation

struct DoseEntry: Codable, Identifiable, Hashable {
    static let defaultUnits = 8.0
    private static let overnightDoseCutoffHour = 6

    let id: UUID
    let date: Date
    let period: InsulinPeriod
    let caregiver: String
    let units: Double

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        period: InsulinPeriod,
        caregiver: String,
        units: Double
    ) {
        self.id = id
        self.date = date
        self.period = period
        self.caregiver = caregiver
        self.units = units
    }

    var cloudRecordName: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: doseDay)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d-%@", year, month, day, period.rawValue)
    }

    var doseDay: Date {
        doseDay(calendar: .current)
    }

    func isOnDoseDay(_ day: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(doseDay(calendar: calendar), inSameDayAs: day)
    }

    func doseDay(calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: date)
        let belongsToPreviousNight = period == .night && hour < Self.overnightDoseCutoffHour
        let referenceDate = belongsToPreviousNight
            ? calendar.date(byAdding: .day, value: -1, to: date) ?? date
            : date

        return calendar.startOfDay(for: referenceDate)
    }
}
