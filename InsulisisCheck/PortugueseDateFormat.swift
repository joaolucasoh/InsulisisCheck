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
        let calendar = Calendar.current
        let timeText = insulisisTimeText

        if calendar.isDateInToday(self) {
            return "hoje, às \(timeText)"
        }

        if calendar.isDateInTomorrow(self) {
            return "amanhã, às \(timeText)"
        }

        return formatted(
            .dateTime
                .locale(Locale(identifier: "pt_BR"))
                .weekday(.abbreviated)
        ) + ", \(timeText)"
    }

    var insulisisTimeText: String {
        Self.insulisisTimeFormatter.string(from: self)
    }

    private static var insulisisTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "h:mm a"
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter
    }

    var insulisisDelayText: String {
        let elapsedSeconds = max(0, Int(Date.now.timeIntervalSince(self)))
        let elapsedMinutes = max(1, elapsedSeconds / 60)
        let hours = elapsedMinutes / 60
        let minutes = elapsedMinutes % 60

        if hours == 0 {
            return "\(minutes) \(minutes == 1 ? "minuto" : "minutos")"
        }

        let hourText = "\(hours) \(hours == 1 ? "hora" : "horas")"
        guard minutes > 0 else { return hourText }

        let minuteText = "\(minutes) \(minutes == 1 ? "minuto" : "minutos")"
        return "\(hourText) e \(minuteText)"
    }
}
