import Foundation

enum AppSessionMode: String, CaseIterable, Identifiable {
    case caregiver
    case testOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caregiver: "Cuidador"
        case .testOnly: "Test only"
        }
    }

    var storageKey: String {
        switch self {
        case .caregiver: SharedStorage.caregiverDoseEntriesKey
        case .testOnly: SharedStorage.testDoseEntriesKey
        }
    }

    var usesCloud: Bool {
        self == .caregiver
    }
}
