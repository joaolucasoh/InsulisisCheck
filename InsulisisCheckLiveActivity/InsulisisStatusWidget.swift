import SwiftUI
import WidgetKit

struct InsulisisStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InsulisisStatusWidget", provider: InsulisisStatusProvider()) { entry in
            InsulisisStatusWidgetView(entry: entry)
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
            "Era para \(nextDoseDate.insulisisTimeText)"
        case .due(_, let nextDoseDate):
            "Aplicar às \(nextDoseDate.insulisisTimeText)"
        case .waiting(_, let nextDoseDate):
            "Próxima dose às \(nextDoseDate.insulisisTimeText)"
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
        default:
            Color.clear
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

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.status.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.status.subtitle)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }

    private var circularAccessory: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(entry.status.tint.opacity(0.22))

            Image(entry.status.imageName)
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(Circle())
                .widgetAccentable(false)
        }
        .frame(width: 58, height: 58)
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
            }
        }
    }

    private func statusText(textScale: WidgetTextScale) -> some View {
        VStack(alignment: .leading, spacing: textScale.spacing) {
            Label(entry.status.title, systemImage: entry.status.symbolName)
                .font(textScale.titleFont)
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(radius: 4, y: 1)

            Text(entry.status.subtitle)
                .font(textScale.subtitleFont)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .shadow(radius: 3, y: 1)
        }
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

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
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

        guard let data = WidgetSharedStorage.defaults.data(forKey: WidgetSharedStorage.doseEntriesKey),
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
    var insulisisTimeText: String {
        formatted(
            .dateTime
                .locale(Locale(identifier: "pt_BR"))
                .hour()
                .minute()
        )
    }
}

#Preview(as: .systemLarge) {
    InsulisisStatusWidget()
} timeline: {
    InsulisisStatusEntry(date: .now, status: .waiting(periodTitle: "Manhã", nextDoseDate: .now.addingTimeInterval(3_600)))
    InsulisisStatusEntry(date: .now, status: .overdue(periodTitle: "Noite", nextDoseDate: .now.addingTimeInterval(-900)))
}
