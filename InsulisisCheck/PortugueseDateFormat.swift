import Foundation

extension Date {
    var insulisisDayText: String {
        formatted(
            .dateTime
                .locale(Locale(identifier: "pt_BR"))
                .weekday(.wide)
                .day()
                .month(.wide)
        )
    }

    var insulisisShortDayTimeText: String {
        formatted(
            .dateTime
                .locale(Locale(identifier: "pt_BR"))
                .weekday(.abbreviated)
                .hour()
                .minute()
        )
    }

    var insulisisTimeText: String {
        formatted(
            .dateTime
                .locale(Locale(identifier: "pt_BR"))
                .hour()
                .minute()
        )
    }
}
