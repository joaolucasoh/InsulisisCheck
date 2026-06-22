import CloudKit
import Foundation

enum CloudSyncStatus: Equatable {
    case idle
    case syncing
    case ready
    case unavailable(String)
}

enum CloudShareDiagnostics {
    private static let key = "insulisis.shareDiagnostics"

    static var text: String {
        SharedStorage.defaults.stringArray(forKey: key)?.joined(separator: "\n") ?? ""
    }

    static func clear() {
        SharedStorage.defaults.removeObject(forKey: key)
    }

    static func record(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)"
        print(line)

        var lines = SharedStorage.defaults.stringArray(forKey: key) ?? []
        lines.append(line)
        lines = Array(lines.suffix(30))
        SharedStorage.defaults.set(lines, forKey: key)
    }
}

enum CloudInviteLink {
    private static let scheme = "insulisischeck"
    private static let host = "accept-share"
    private static let shareQueryItemName = "share"

    static func appURL(for shareURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: shareQueryItemName, value: shareURL.absoluteString)
        ]
        return components.url
    }

    static func shareURL(from appURL: URL) -> URL? {
        guard appURL.scheme == scheme,
              appURL.host == host,
              let components = URLComponents(url: appURL, resolvingAgainstBaseURL: false),
              let shareURLString = components.queryItems?.first(where: { $0.name == shareQueryItemName })?.value else {
            return nil
        }

        return URL(string: shareURLString)
    }

    static func shareURL(fromText text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmed) {
            if let shareURL = shareURL(from: url) {
                return shareURL
            }

            if isCloudKitShareURL(url) {
                return url
            }
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url else { continue }

            if let shareURL = shareURL(from: url) {
                return shareURL
            }

            if isCloudKitShareURL(url) {
                return url
            }
        }

        return nil
    }

    private static func isCloudKitShareURL(_ url: URL) -> Bool {
        url.scheme?.localizedCaseInsensitiveCompare("https") == .orderedSame &&
            url.host?.localizedCaseInsensitiveCompare("www.icloud.com") == .orderedSame &&
            url.path.localizedCaseInsensitiveContains("/share/")
    }
}

enum CloudErrorMessage {
    static func make(from error: Error) -> String {
        let description = error.localizedDescription

        if description.localizedCaseInsensitiveContains("recordName") &&
            description.localizedCaseInsensitiveContains("queryable") {
            return """
            O CloudKit Production está sem um índice necessário.

            No CloudKit Dashboard, vá em Development > Schema > Indexes e adicione recordName como queryable no tipo cloudkit.share. Se o Dashboard também mostrar recordName em InsulisisFamily, marque queryable nele também. Depois faça Deploy Schema Changes para Production e tente aceitar o convite novamente.

            Detalhes técnicos: \(description)
            """
        }

        if let ckError = error as? CKError {
            if ckError.code == .permissionFailure {
                return """
                O iCloud recusou acesso ao histórico compartilhado.

                Confira no CloudKit Dashboard em Production se o tipo DoseEntry existe no Public Database e se as Security Roles permitem que usuários iCloud criem, leiam, editem e apaguem DoseEntry. Depois faça Deploy Schema Changes para Production e tente sincronizar novamente.

                Detalhes técnicos: \(ckError.localizedDescription)
                Código CloudKit: \(ckError.code.rawValue)
                """
            }

            return """
            O iCloud recusou a operação.

            Detalhes técnicos: \(ckError.localizedDescription)
            Código CloudKit: \(ckError.code.rawValue)
            """
        }

        return description
    }
}

final class CloudDoseSync {
    static let shared = CloudDoseSync()

    let container = CKContainer(identifier: "iCloud.com.raven.InsulisisCheck")

    private let zoneName = "InsulisisFamilyZone"
    private let rootRecordName = "isis-family"
    private let doseRecordType = "DoseEntry"
    private let familyRecordType = "InsulisisFamily"
    private let caregiverSessionID = "isis-caregiver"
    private let sharedZoneNameKey = "insulisis.sharedZoneName"
    private let sharedZoneOwnerKey = "insulisis.sharedZoneOwner"

    private init() {}

    func fetchCaregiverEntries() async throws -> [DoseEntry] {
        return try await fetchEntries(
            database: container.publicCloudDatabase,
            zoneID: nil,
            predicate: NSPredicate(value: true)
        )
    }

    func saveCaregiverEntry(_ entry: DoseEntry) async throws {
        let recordID = CKRecord.ID(recordName: caregiverRecordName(for: entry))
        let record = CKRecord(recordType: doseRecordType, recordID: recordID)
        fill(record, with: entry)

        _ = try await save(record, in: container.publicCloudDatabase)
    }

    func deleteCaregiverEntry(_ entry: DoseEntry) async throws {
        let recordID = CKRecord.ID(recordName: caregiverRecordName(for: entry))
        try await delete(recordID, in: container.publicCloudDatabase)
    }

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

    func preparedShare() async throws -> (share: CKShare, container: CKContainer, invitationURL: URL) {
        CloudShareDiagnostics.clear()
        CloudShareDiagnostics.record("preparedShare:start")

        CloudShareDiagnostics.record("preparedShare:ensurePrivateZone:start")
        try await ensurePrivateZone()
        CloudShareDiagnostics.record("preparedShare:ensurePrivateZone:done")

        CloudShareDiagnostics.record("preparedShare:rootRecord:start")
        let root = try await rootRecord()
        CloudShareDiagnostics.record("preparedShare:rootRecord:done \(root.recordID.recordName)")

        CloudShareDiagnostics.record("preparedShare:existingShare:start")
        let share = try await existingShare(for: root) ?? CKShare(rootRecord: root)
        CloudShareDiagnostics.record("preparedShare:existingShare:done \(share.recordID.recordName)")

        share[CKShare.SystemFieldKey.title] = "Insulísis Check" as CKRecordValue
        share.publicPermission = .readWrite

        CloudShareDiagnostics.record("preparedShare:modify:start")
        try await modify(recordsToSave: [root, share], in: container.privateCloudDatabase)
        CloudShareDiagnostics.record("preparedShare:modify:done")

        CloudShareDiagnostics.record("preparedShare:shareURL:start")
        guard let invitationURL = share.url else {
            CloudShareDiagnostics.record("preparedShare:shareURL:nil")
            throw CKError(.unknownItem)
        }
        CloudShareDiagnostics.record("preparedShare:shareURL:done \(invitationURL.absoluteString)")

        return (share, container, invitationURL)
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

    func shareMetadata(from shareURL: URL) async throws -> CKShare.Metadata {
        CloudShareDiagnostics.record("shareMetadata:start \(shareURL.absoluteString)")

        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareMetadataOperation(shareURLs: [shareURL])
            operation.shouldFetchRootRecord = true

            var fetchedMetadata: CKShare.Metadata?
            var fetchError: Error?

            operation.perShareMetadataResultBlock = { _, result in
                switch result {
                case .success(let metadata):
                    CloudShareDiagnostics.record("shareMetadata:perURL:success")
                    fetchedMetadata = metadata
                case .failure(let error):
                    CloudShareDiagnostics.record("shareMetadata:perURL:error \(error.localizedDescription)")
                    fetchError = error
                }
            }

            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let fetchedMetadata {
                        CloudShareDiagnostics.record("shareMetadata:done")
                        continuation.resume(returning: fetchedMetadata)
                    } else {
                        CloudShareDiagnostics.record("shareMetadata:nil")
                        continuation.resume(throwing: fetchError ?? CKError(.unknownItem))
                    }
                case .failure(let error):
                    CloudShareDiagnostics.record("shareMetadata:error \(error.localizedDescription)")
                    continuation.resume(throwing: fetchError ?? error)
                }
            }

            container.add(operation)
        }
    }

    private func existingShare(for root: CKRecord) async throws -> CKShare? {
        guard let shareReference = root.share else { return nil }
        let share = try await fetchRecord(shareReference.recordID, in: container.privateCloudDatabase)
        return share as? CKShare
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
        try await fetchEntries(
            database: database,
            zoneID: zoneID,
            predicate: NSPredicate(value: true)
        )
    }

    private func fetchEntries(database: CKDatabase, zoneID: CKRecordZone.ID?, predicate: NSPredicate) async throws -> [DoseEntry] {
        try await withCheckedThrowingContinuation { continuation in
            let query = CKQuery(recordType: doseRecordType, predicate: predicate)

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
                    continuation.resume(returning: self.deduplicated(records.compactMap(Self.entry(from:))))
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

    private func caregiverRecordName(for entry: DoseEntry) -> String {
        "\(caregiverSessionID)-\(entry.cloudRecordName)"
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
