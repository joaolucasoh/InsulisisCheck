import Combine
import CloudKit
import Foundation
import WidgetKit

@MainActor
final class DoseStore: ObservableObject {
    static let shared = DoseStore()

    @Published private(set) var entries: [DoseEntry] = []
    @Published private(set) var syncStatus: CloudSyncStatus = .idle

    private let storageKey = SharedStorage.doseEntriesKey
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func record(period: InsulinPeriod, caregiver: String, units: Double, date: Date = Date()) {
        let cleanName = caregiver.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = DoseEntry(
            date: date,
            period: period,
            caregiver: cleanName.isEmpty ? "Não informado" : cleanName,
            units: max(0, units)
        )

        entries.removeAll {
            Calendar.current.isDate($0.date, inSameDayAs: date) && $0.period == period
        }
        entries.append(entry)
        entries.sort { $0.date > $1.date }
        save()

        Task {
            await syncEntry(entry)
            await InsulinActivityManager.shared.dismissActivity(for: period)
            await InsulinNotificationManager.shared.refresh(entries: entries)
        }
    }

    func syncFromCloud() async {
        syncStatus = .syncing

        do {
            let cloudEntries = try await CloudDoseSync.shared.fetchEntries()
            merge(cloudEntries)
            syncStatus = .ready
            await InsulinNotificationManager.shared.refresh(entries: entries)
        } catch {
            syncStatus = .unavailable(error.localizedDescription)
        }
    }

    func syncShareAcceptance(_ metadata: CKShare.Metadata) async {
        syncStatus = .syncing

        do {
            try await CloudDoseSync.shared.acceptShare(metadata: metadata)
            await syncFromCloud()
        } catch {
            syncStatus = .unavailable(error.localizedDescription)
        }
    }

    func entry(for period: InsulinPeriod, on date: Date = Date()) -> DoseEntry? {
        entries.first {
            Calendar.current.isDate($0.date, inSameDayAs: date) && $0.period == period
        }
    }

    func entries(on date: Date = Date()) -> [DoseEntry] {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func isComplete(period: InsulinPeriod, on date: Date = Date()) -> Bool {
        entry(for: period, on: date) != nil
    }

    private func load() {
        migrateLegacyEntriesIfNeeded()

        guard let data = SharedStorage.defaults.data(forKey: storageKey) else {
            entries = []
            return
        }

        entries = (try? decoder.decode([DoseEntry].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? encoder.encode(entries) else { return }
        SharedStorage.defaults.set(data, forKey: storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func syncEntry(_ entry: DoseEntry) async {
        syncStatus = .syncing

        do {
            try await CloudDoseSync.shared.save(entry)
            syncStatus = .ready
            await InsulinNotificationManager.shared.refresh(entries: entries)
        } catch {
            syncStatus = .unavailable(error.localizedDescription)
        }
    }

    private func merge(_ cloudEntries: [DoseEntry]) {
        guard !cloudEntries.isEmpty else { return }

        var merged = Dictionary(uniqueKeysWithValues: entries.map { ($0.cloudRecordName, $0) })
        for entry in cloudEntries {
            merged[entry.cloudRecordName] = entry
        }

        entries = merged.values.sorted { $0.date > $1.date }
        save()
    }

    private func migrateLegacyEntriesIfNeeded() {
        guard SharedStorage.defaults.data(forKey: storageKey) == nil,
              let legacyData = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }

        SharedStorage.defaults.set(legacyData, forKey: storageKey)
    }
}
