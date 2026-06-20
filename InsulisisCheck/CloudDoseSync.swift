import CloudKit
import Foundation

enum CloudSyncStatus: Equatable {
    case idle
    case syncing
    case ready
    case unavailable(String)
}

final class CloudDoseSync {
    static let shared = CloudDoseSync()

    let container = CKContainer(identifier: "iCloud.com.raven.InsulisisCheck")

    private let zoneName = "InsulisisFamilyZone"
    private let rootRecordName = "isis-family"
    private let doseRecordType = "DoseEntry"
    private let familyRecordType = "InsulisisFamily"
    private let sharedZoneNameKey = "insulisis.sharedZoneName"
    private let sharedZoneOwnerKey = "insulisis.sharedZoneOwner"

    private init() {}

    func fetchEntries() async throws -> [DoseEntry] {
        try await ensurePrivateZone()

        var entries = try await fetchEntries(
            database: container.privateCloudDatabase,
            zoneID: privateZoneID
        )

        let sharedZones = try await fetchSharedZones()
        for zone in sharedZones {
            let sharedEntries = try await fetchEntries(
                database: container.sharedCloudDatabase,
                zoneID: zone.zoneID
            )
            entries.append(contentsOf: sharedEntries)
        }

        return deduplicated(entries)
    }

    func save(_ entry: DoseEntry) async throws {
        try await ensurePrivateZone()

        let target = try await writableTarget()
        let recordID = CKRecord.ID(recordName: entry.cloudRecordName, zoneID: target.zoneID)
        let record = CKRecord(recordType: doseRecordType, recordID: recordID)
        fill(record, with: entry)

        _ = try await save(record, in: target.database)
    }

    func delete(_ entry: DoseEntry) async throws {
        try await ensurePrivateZone()

        let target = try await writableTarget()
        let recordID = CKRecord.ID(recordName: entry.cloudRecordName, zoneID: target.zoneID)
        try await delete(recordID, in: target.database)
    }

    func prepareShare(completion: @escaping (CKShare?, CKContainer?, Error?) -> Void) {
        Task {
            do {
                let preparedShare = try await preparedShare()
                completion(preparedShare.share, preparedShare.container, nil)
            } catch {
                completion(nil, container, error)
            }
        }
    }

    func preparedShare() async throws -> (share: CKShare, container: CKContainer) {
        try await ensurePrivateZone()
        try await deleteExistingShareIfNeeded()

        let root = try await rootRecord()
        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Insulísis Check" as CKRecordValue
        share.publicPermission = .readWrite

        try await modify(recordsToSave: [root, share], in: container.privateCloudDatabase)
        return (share, container)
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    guard let rootRecordID = metadata.hierarchicalRootRecordID else {
                        continuation.resume(throwing: CKError(.unknownItem))
                        return
                    }
                    SharedStorage.defaults.set(rootRecordID.zoneID.zoneName, forKey: self.sharedZoneNameKey)
                    SharedStorage.defaults.set(rootRecordID.zoneID.ownerName, forKey: self.sharedZoneOwnerKey)
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    private func deleteExistingShareIfNeeded() async throws {
        let rootRecordID = CKRecord.ID(recordName: rootRecordName, zoneID: privateZoneID)
        let root = try await fetchRecord(rootRecordID, in: container.privateCloudDatabase)
        guard let shareReference = root.share else { return }
        try await delete(shareReference.recordID, in: container.privateCloudDatabase)
    }

    private var privateZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    private func writableTarget() async throws -> (database: CKDatabase, zoneID: CKRecordZone.ID) {
        if let zoneName = SharedStorage.defaults.string(forKey: sharedZoneNameKey),
           let ownerName = SharedStorage.defaults.string(forKey: sharedZoneOwnerKey) {
            return (
                container.sharedCloudDatabase,
                CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
            )
        }

        return (container.privateCloudDatabase, privateZoneID)
    }

    private func ensurePrivateZone() async throws {
        let zones = try await fetchPrivateZones()
        if zones.contains(where: { $0.zoneID.zoneName == zoneName }) {
            _ = try await rootRecord()
            return
        }

        let zone = CKRecordZone(zoneID: privateZoneID)
        _ = try await save(zone, in: container.privateCloudDatabase)
        _ = try await rootRecord()
    }

    private func rootRecord() async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: rootRecordName, zoneID: privateZoneID)

        do {
            return try await fetchRecord(recordID, in: container.privateCloudDatabase)
        } catch let error as CKError where error.code == .unknownItem {
            let record = CKRecord(recordType: familyRecordType, recordID: recordID)
            record["name"] = "Isis" as CKRecordValue
            return try await save(record, in: container.privateCloudDatabase)
        }
    }

    private func fetchSharedZones() async throws -> [CKRecordZone] {
        try await withCheckedThrowingContinuation { continuation in
            container.sharedCloudDatabase.fetchAllRecordZones { zones, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: zones ?? [])
            }
        }
    }

    private func fetchPrivateZones() async throws -> [CKRecordZone] {
        try await withCheckedThrowingContinuation { continuation in
            container.privateCloudDatabase.fetchAllRecordZones { zones, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: zones ?? [])
            }
        }
    }

    private func fetchEntries(database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [DoseEntry] {
        try await withCheckedThrowingContinuation { continuation in
            let query = CKQuery(recordType: doseRecordType, predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

            let operation = CKQueryOperation(query: query)
            operation.zoneID = zoneID

            var records: [CKRecord] = []
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    records.append(record)
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: records.compactMap(Self.entry(from:)))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    private func save(_ zone: CKRecordZone, in database: CKDatabase) async throws -> CKRecordZone {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: zone)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func save(_ record: CKRecord, in database: CKDatabase) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: record ?? CKRecord(recordType: self.doseRecordType))
            }
        }
    }

    private func modify(recordsToSave: [CKRecord], in database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func delete(_ recordID: CKRecord.ID, in database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { continuation in
            database.delete(withRecordID: recordID) { _, error in
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    continuation.resume()
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume()
            }
        }
    }

    private func fetchRecord(_ recordID: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let record else {
                    continuation.resume(throwing: CKError(.unknownItem))
                    return
                }

                continuation.resume(returning: record)
            }
        }
    }

    private func fill(_ record: CKRecord, with entry: DoseEntry) {
        record["date"] = entry.date as CKRecordValue
        record["period"] = entry.period.rawValue as CKRecordValue
        record["caregiver"] = entry.caregiver as CKRecordValue
        record["units"] = entry.units as CKRecordValue
    }

    private static func entry(from record: CKRecord) -> DoseEntry? {
        guard let date = record["date"] as? Date,
              let periodValue = record["period"] as? String,
              let period = InsulinPeriod(rawValue: periodValue),
              let caregiver = record["caregiver"] as? String,
              let units = record["units"] as? Double else {
            return nil
        }

        return DoseEntry(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            date: date,
            period: period,
            caregiver: caregiver,
            units: units
        )
    }

    private func deduplicated(_ entries: [DoseEntry]) -> [DoseEntry] {
        var byRecordName: [String: DoseEntry] = [:]

        for entry in entries {
            byRecordName[entry.cloudRecordName] = entry
        }

        return byRecordName.values.sorted { $0.date > $1.date }
    }
}
