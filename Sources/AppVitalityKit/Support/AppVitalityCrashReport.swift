import Foundation

struct AppVitalityCrashReport: Codable {
    let title: String
    let stackTrace: String
    let logString: String
    let observedAt: Date
    let breadcrumbs: [[String: AnyEncodable]]?
    let environment: [String: AnyEncodable]?
}
