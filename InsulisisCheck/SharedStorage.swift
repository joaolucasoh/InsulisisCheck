import Foundation

enum SharedStorage {
    static let appGroupID = "group.com.raven.InsulisisCheck"
    static let doseEntriesKey = "insulisis.doseEntries"
    static let caregiverDoseEntriesKey = "insulisis.doseEntries.caregiver"
    static let testDoseEntriesKey = "insulisis.doseEntries.testOnly"
    static let sessionModeKey = "insulisis.sessionMode"
    static let lastSyncDateKey = "insulisis.lastSyncDate"
    static let deviceIDKey = "insulisis.deviceID"
    static let remoteDoseNotificationIDsKey = "insulisis.remoteDoseNotificationIDs"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var deviceID: String {
        if let existingID = defaults.string(forKey: deviceIDKey) {
            return existingID
        }

        let newID = UUID().uuidString
        defaults.set(newID, forKey: deviceIDKey)
        return newID
    }
}
