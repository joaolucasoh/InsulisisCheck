import SwiftUI
import WidgetKit

struct InsulisisStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InsulisisStatusWidget", provider: InsulisisStatusProvider()) { entry in
            InsulisisStatusWidgetView(entry: entry)
                .accessibilityIdentifier("widget.status.root")
        }
        .configurationDisplayName("Insulísis Check")
        .description("Mostra se a dose da Isis está atrasada ou aguardando o próximo horário.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

private struct InsulisisStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> InsulisisStatusEntry {
        InsulisisStatusEntry(date: .now, status: .waiting(periodTitle: "Manhã", nextDoseDate: .now.addingTimeInterval(3_600)))
    }

    func getSnapshot(in context: Context, completion: @escaping (InsulisisStatusEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InsulisisStatusEntry>) -> Void) {
        let entry = makeEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeEntry(now: Date = .now) -> InsulisisStatusEntry {
        InsulisisStatusEntry(date: now, status: InsulisisWidgetStatus.make(now: now))
    }
}

private struct InsulisisStatusEntry: TimelineEntry {
    let date: Date
    let status: InsulisisWidgetStatus
}

private enum InsulisisWidgetStatus {
    case overdue(periodTitle: String, nextDoseDate: Date)
    case due(periodTitle: String, nextDoseDate: Date)
    case waiting(periodTitle: String, nextDoseDate: Date)

    var title: String {
        switch self {
        case .overdue(let periodTitle, _):
            "Dose da \(periodTitle) atrasada"
        case .due(let periodTitle, _):
            "Hora da dose da \(periodTitle)"
        case .waiting:
            "Zizi tá de boa"
        }
    }

    var subtitle: String {
        switch self {
        case .overdue(_, let nextDoseDate):
            "Atrasada \(nextDoseDate.insulisisDelayText)"
        case .due(_, let nextDoseDate):
            "Aplicar \(nextDoseDate.insulisisShortDayTimeText)"
        case .waiting(_, let nextDoseDate):
            "Próxima dose \(nextDoseDate.insulisisShortDayTimeText)"
        }
    }

    var imageName: String {
        switch self {
        case .overdue: "IsisWaiting"
        case .due: "IsisDue"
        case .waiting: "IsisNeutral"
        }
    }

    var tint: Color {
        switch self {
        case .overdue: .red
        case .due: .orange
        case .waiting: .green
        }
    }

    var symbolName: String {
        switch self {
        case .overdue: "clock.badge.exclamationmark"
        case .due: "syringe"
        case .waiting: "checkmark.seal.fill"
        }
    }

    static func make(now: Date) -> InsulisisWidgetStatus {
        let entries = DoseEntrySnapshot.allEntries()
        let schedule = DoseScheduleSnapshot.make(entries: entries, now: now)

        if schedule.isOverdue(at: now) {
            return .overdue(periodTitle: schedule.nextPeriod.title, nextDoseDate: schedule.nextDoseDate)
        }

        if schedule.isDue(at: now) {
            return .due(periodTitle: schedule.nextPeriod.title, nextDoseDate: schedule.nextDoseDate)
        }

        return .waiting(periodTitle: schedule.nextPeriod.title, nextDoseDate: schedule.nextDoseDate)
    }
}

private struct InsulisisStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: InsulisisStatusEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                widgetBackground
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemLarge:
            largeWidget
        case .systemMedium:
            mediumWidget
        case .accessoryInline:
            Text("\(Image(systemName: entry.status.symbolName)) \(entry.status.title)")
                .accessibilityIdentifier("widget.status.accessory-inline.label")
        case .accessoryCircular:
            circularAccessory
        case .accessoryRectangular:
            rectangularAccessory
        default:
            smallWidget
        }
    }

    @ViewBuilder
    private var widgetBackground: some View {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge:
            Image(entry.status.imageName)
                .resizable()
                .scaledToFill()
                .accessibilityIdentifier("widget.status.background-image")
        default:
            Color.clear
                .accessibilityIdentifier("widget.status.clear-background")
        }
    }

    private var largeWidget: some View {
        fullBleedWidget(textScale: .large)
    }

    private var mediumWidget: some View {
        fullBleedWidget(textScale: .medium)
    }

    private var smallWidget: some View {
        fullBleedWidget(textScale: .small)
    }

    private var rectangularAccessory: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(entry.status.imageName)
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .widgetAccentable(false)
                .accessibilityIdentifier("widget.status.rectangular.image")

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.status.title)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("widget.status.rectangular.title")
                Text(entry.status.subtitle)
                    .font(.caption)
                    .lineLimit(1)
                    .accessibilityIdentifier("widget.status.rectangular.subtitle")
            }
            .accessibilityIdentifier("widget.status.rectangular.text-stack")
        }
        .accessibilityIdentifier("widget.status.rectangular.container")
    }

    private var circularAccessory: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(entry.status.tint.opacity(0.22))
                .accessibilityIdentifier("widget.status.circular.background")

            Image(entry.status.imageName)
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(Circle())
                .widgetAccentable(false)
                .accessibilityIdentifier("widget.status.circular.image")
        }
        .frame(width: 58, height: 58)
        .accessibilityIdentifier("widget.status.circular.container")
    }

    private func fullBleedWidget(textScale: WidgetTextScale) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                entry.status.tint.opacity(0.28)

                Image(entry.status.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .accessibilityIdentifier("widget.status.full-bleed.image")

                LinearGradient(
                    colors: [
                        .black.opacity(0),
                        .black.opacity(0.16),
                        .black.opacity(0.66)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                statusText(textScale: textScale)
                    .padding(textScale.padding)
                    .accessibilityIdentifier("widget.status.full-bleed.text-stack")
            }
            .accessibilityIdentifier("widget.status.full-bleed.container")
        }
    }

    private func statusText(textScale: WidgetTextScale) -> some View {
        VStack(alignment: .leading, spacing: textScale.spacing) {
            Label(entry.status.title, systemImage: entry.status.symbolName)
                .font(textScale.titleFont)
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(radius: 4, y: 1)
                .accessibilityIdentifier("widget.status.title-label")

            Text(entry.status.subtitle)
                .font(textScale.subtitleFont)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .shadow(radius: 3, y: 1)
                .accessibilityIdentifier("widget.status.subtitle-label")
        }
        .accessibilityIdentifier("widget.status.text-stack")
    }
}

private enum WidgetTextScale {
    case small
    case medium
    case large

    var titleFont: Font {
        switch self {
        case .small: .headline
        case .medium: .title3.bold()
        case .large: .title2.bold()
        }
    }

    var subtitleFont: Font {
        switch self {
        case .small: .caption
        case .medium: .subheadline
        case .large: .headline
        }
    }

    var spacing: CGFloat {
        switch self {
        case .small: 3
        case .medium: 5
        case .large: 7
        }
    }

    var padding: CGFloat {
        switch self {
        case .small: 14
        case .medium: 16
        case .large: 20
        }
    }
}

private enum WidgetSharedStorage {
    static let appGroupID = "group.com.raven.InsulisisCheck"
    static let doseEntriesKey = "insulisis.doseEntries"
    static let caregiverDoseEntriesKey = "insulisis.doseEntries.caregiver"
    static let testDoseEntriesKey = "insulisis.doseEntries.testOnly"
    static let sessionModeKey = "insulisis.sessionMode"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var activeDoseEntriesKey: String {
        switch defaults.string(forKey: sessionModeKey) {
        case "testOnly":
            testDoseEntriesKey
        case "caregiver":
            caregiverDoseEntriesKey
        default:
            defaults.data(forKey: caregiverDoseEntriesKey) == nil ? doseEntriesKey : caregiverDoseEntriesKey
        }
    }
}

private enum InsulinPeriodSnapshot: String, Codable, CaseIterable {
    case morning
    case night

    var title: String {
        switch self {
        case .morning: "Manhã"
        case .night: "Noite"
        }
    }

    var deadlineHour: Int {
        switch self {
        case .morning: 8
        case .night: 20
        }
    }

    func deadline(on date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: deadlineHour, minute: 0, second: 0, of: date) ?? date
    }

    var next: InsulinPeriodSnapshot {
        switch self {
        case .morning: .night
        case .night: .morning
        }
    }
}

private struct DoseEntrySnapshot: Codable {
    let date: Date
    let period: InsulinPeriodSnapshot

    static func allEntries() -> [DoseEntrySnapshot] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = WidgetSharedStorage.defaults.data(forKey: WidgetSharedStorage.activeDoseEntriesKey),
              let entries = try? decoder.decode([DoseEntrySnapshot].self, from: data) else {
            return []
        }

        return entries
    }
}

private struct DoseScheduleSnapshot {
    static let overdueGracePeriod: TimeInterval = 15 * 60

    let nextPeriod: InsulinPeriodSnapshot
    let nextDoseDate: Date

    func isDue(at date: Date) -> Bool {
        date >= nextDoseDate && !isOverdue(at: date)
    }

    func isOverdue(at date: Date) -> Bool {
        date >= nextDoseDate.addingTimeInterval(Self.overdueGracePeriod)
    }

    static func make(entries: [DoseEntrySnapshot], now: Date, calendar: Calendar = .current) -> DoseScheduleSnapshot {
        if let latestEntry = entries.max(by: { $0.date < $1.date }) {
            let nextDate = calendar.date(byAdding: .hour, value: 12, to: latestEntry.date) ?? latestEntry.date.addingTimeInterval(43_200)
            return DoseScheduleSnapshot(nextPeriod: latestEntry.period.next, nextDoseDate: nextDate)
        }

        let morning = InsulinPeriodSnapshot.morning.deadline(on: now, calendar: calendar)
        if now < morning {
            return DoseScheduleSnapshot(nextPeriod: .morning, nextDoseDate: morning)
        }

        let night = InsulinPeriodSnapshot.night.deadline(on: now, calendar: calendar)
        if now < night {
            return DoseScheduleSnapshot(nextPeriod: .night, nextDoseDate: night)
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        return DoseScheduleSnapshot(nextPeriod: .morning, nextDoseDate: InsulinPeriodSnapshot.morning.deadline(on: tomorrow, calendar: calendar))
    }
}

private extension Date {
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
