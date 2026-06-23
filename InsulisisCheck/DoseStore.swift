import Combine
import CloudKit
import Foundation
import WidgetKit

@MainActor
final class DoseStore: ObservableObject {
    static let shared = DoseStore()

    @Published private(set) var entries: [DoseEntry] = []
    @Published private(set) var syncStatus: CloudSyncStatus = .idle
    @Published private(set) var sessionMode: AppSessionMode?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        sessionMode = SharedStorage.defaults.string(forKey: SharedStorage.sessionModeKey)
            .flatMap(AppSessionMode.init(rawValue:))
        load()
    }

    func selectSessionMode(_ mode: AppSessionMode) {
        sessionMode = mode
        SharedStorage.defaults.set(mode.rawValue, forKey: SharedStorage.sessionModeKey)
        load()

        if mode.usesCloud {
            Task { await syncFromCloud() }
        } else {
            syncStatus = .idle
        }
    }

    func clearSessionMode() {
        sessionMode = nil
        entries = []
        syncStatus = .idle
        SharedStorage.defaults.removeObject(forKey: SharedStorage.sessionModeKey)
        WidgetCenter.shared.reloadAllTimelines()
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
            $0.period == period && $0.isOnDoseDay(entry.doseDay)
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

    func markPending(period: InsulinPeriod, on date: Date = Date()) {
        guard let entry = entry(for: period, on: date) else { return }

        entries.removeAll { $0.cloudRecordName == entry.cloudRecordName }
        entries.sort { $0.date > $1.date }
        save()

        Task {
            await deleteEntry(entry)
            await InsulinActivityManager.shared.refresh(store: self)
            await InsulinNotificationManager.shared.refresh(entries: entries)
        }
    }

    func syncFromCloud() async {
        guard sessionMode?.usesCloud == true else {
            syncStatus = .idle
            return
        }

        syncStatus = .syncing

        do {
            let cloudEntries = try await CloudDoseSync.shared.fetchCaregiverEntries()

            if cloudEntries.isEmpty {
                if try await uploadLocalCaregiverEntries() > 0 {
                    let refreshedCloudEntries = try await CloudDoseSync.shared.fetchCaregiverEntries()
                    merge(refreshedCloudEntries)
                }
            } else {
                merge(cloudEntries)
            }

            syncStatus = .ready("Dados sincronizados.")
            await InsulinNotificationManager.shared.refresh(entries: entries)
        } catch {
            syncStatus = .unavailable(CloudErrorMessage.make(from: error))
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

    func syncShareInvitation(from shareURL: URL) async {
        syncStatus = .syncing

        do {
            CloudShareDiagnostics.record("syncShareInvitation:metadata:start")
            let metadata = try await CloudDoseSync.shared.shareMetadata(from: shareURL)
            CloudShareDiagnostics.record("syncShareInvitation:metadata:done")
            CloudShareDiagnostics.record("syncShareInvitation:accept:start")
            try await CloudDoseSync.shared.acceptShare(metadata: metadata)
            CloudShareDiagnostics.record("syncShareInvitation:accept:done")
            CloudShareDiagnostics.record("syncShareInvitation:sync:start")
            await syncFromCloud()
            CloudShareDiagnostics.record("syncShareInvitation:sync:done")
        } catch {
            CloudShareDiagnostics.record("syncShareInvitation:error \(error.localizedDescription)")
            syncStatus = .unavailable(CloudErrorMessage.make(from: error))
        }
    }

    func entry(for period: InsulinPeriod, on date: Date = Date()) -> DoseEntry? {
        entries.first {
            $0.period == period && $0.isOnDoseDay(date)
        }
    }

    func entries(on date: Date = Date()) -> [DoseEntry] {
        entries.filter { $0.isOnDoseDay(date) }
    }

    func isComplete(period: InsulinPeriod, on date: Date = Date()) -> Bool {
        entry(for: period, on: date) != nil
    }

    private func load() {
        migrateLegacyEntriesIfNeeded()

        guard let storageKey,
              let data = SharedStorage.defaults.data(forKey: storageKey) else {
            entries = []
            return
        }

        entries = (try? decoder.decode([DoseEntry].self, from: data)) ?? []
    }

    private func save() {
        guard let storageKey else { return }
        guard let data = try? encoder.encode(entries) else { return }
        SharedStorage.defaults.set(data, forKey: storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func syncEntry(_ entry: DoseEntry) async {
        guard sessionMode?.usesCloud == true else {
            syncStatus = .idle
            return
        }

        syncStatus = .syncing

        do {
            try await CloudDoseSync.shared.saveCaregiverEntry(entry)
            syncStatus = .ready("Dados sincronizados.")
            await InsulinNotificationManager.shared.refresh(entries: entries)
        } catch {
            syncStatus = .unavailable(CloudErrorMessage.make(from: error))
        }
    }

    private func deleteEntry(_ entry: DoseEntry) async {
        guard sessionMode?.usesCloud == true else {
            syncStatus = .idle
            return
        }

        syncStatus = .syncing

        do {
            try await CloudDoseSync.shared.deleteCaregiverEntry(entry)
            syncStatus = .ready("Dados sincronizados.")
            await InsulinNotificationManager.shared.refresh(entries: entries)
        } catch {
            syncStatus = .unavailable(CloudErrorMessage.make(from: error))
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

    private func uploadLocalCaregiverEntries() async throws -> Int {
        guard sessionMode?.usesCloud == true else { return 0 }

        var uploadedCount = 0
        for entry in entries {
            try await CloudDoseSync.shared.saveCaregiverEntry(entry)
            uploadedCount += 1
        }

        return uploadedCount
    }

    private func migrateLegacyEntriesIfNeeded() {
        let legacyData = SharedStorage.defaults.data(forKey: SharedStorage.doseEntriesKey)
            ?? UserDefaults.standard.data(forKey: SharedStorage.doseEntriesKey)

        guard let legacyData else {
            return
        }

        guard let legacyEntries = try? decoder.decode([DoseEntry].self, from: legacyData),
              !legacyEntries.isEmpty else {
            return
        }

        let currentData = SharedStorage.defaults.data(forKey: SharedStorage.caregiverDoseEntriesKey)
        let currentEntries = currentData.flatMap { try? decoder.decode([DoseEntry].self, from: $0) } ?? []

        var merged = Dictionary(uniqueKeysWithValues: currentEntries.map { ($0.cloudRecordName, $0) })
        for entry in legacyEntries {
            merged[entry.cloudRecordName] = entry
        }

        guard let mergedData = try? encoder.encode(merged.values.sorted(by: { $0.date > $1.date })) else {
            return
        }

        SharedStorage.defaults.set(mergedData, forKey: SharedStorage.caregiverDoseEntriesKey)
    }

    private var storageKey: String? {
        sessionMode?.storageKey
    }
}
