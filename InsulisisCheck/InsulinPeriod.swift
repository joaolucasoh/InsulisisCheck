import Foundation

enum InsulinPeriod: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case morning
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: "Manhã"
        case .night: "Noite"
        }
    }

    var spokenTitle: String {
        switch self {
        case .morning: "manha"
        case .night: "noite"
        }
    }

    var deadlineHour: Int {
        switch self {
        case .morning: 8
        case .night: 20
        }
    }

    func deadline(on date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(
            bySettingHour: deadlineHour,
            minute: 0,
            second: 0,
            of: date
        ) ?? date
    }

    var next: InsulinPeriod {
        switch self {
        case .morning: .night
        case .night: .morning
        }
    }
}
