import Foundation

struct DoseEntry: Codable, Identifiable, Hashable {
    static let defaultUnits = 8.0

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
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d-%@", year, month, day, period.rawValue)
    }
}
