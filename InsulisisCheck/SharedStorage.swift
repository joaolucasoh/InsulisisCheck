import Foundation

enum SharedStorage {
    static let appGroupID = "group.com.raven.InsulisisCheck"
    static let doseEntriesKey = "insulisis.doseEntries"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}
