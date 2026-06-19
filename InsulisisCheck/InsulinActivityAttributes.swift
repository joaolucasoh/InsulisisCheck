import ActivityKit
import Foundation

struct InsulinActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var periodTitle: String
        var overdueStartedAt: Date
        var isOverdue: Bool
    }

    var periodID: String
    var dogName: String
}
