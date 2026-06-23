import Foundation

enum SharedStorage {
    static let appGroupID = "group.com.raven.InsulisisCheck"
    static let doseEntriesKey = "insulisis.doseEntries"
    static let caregiverDoseEntriesKey = "insulisis.doseEntries.caregiver"
    static let testDoseEntriesKey = "insulisis.doseEntries.testOnly"
    static let sessionModeKey = "insulisis.sessionMode"
    static let lastSyncDateKey = "insulisis.lastSyncDate"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}
