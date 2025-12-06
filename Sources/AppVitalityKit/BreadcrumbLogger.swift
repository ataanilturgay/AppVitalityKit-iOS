import Foundation

/// "Black Box" that keeps user's last actions (breadcrumbs) in RAM.
/// These steps are included in the report at crash time.
public class BreadcrumbLogger {
    
    public static let shared = BreadcrumbLogger()
    
    private var logs: [String] = []
    private let maxLogs = 50 // Keep last 50 actions
    private let queue = DispatchQueue(label: "com.batteryfriendly.breadcrumbs", qos: .utility)
    
    private init() {}
    
    /// Records an event or screen transition.
    /// - Parameter message: e.g. "Login button tapped", "HomeView appeared".
    public func log(_ message: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let entry = "[\(timestamp)] \(message)"
            
            self.logs.append(entry)
            
            if self.logs.count > self.maxLogs {
                self.logs.removeFirst()
            }
        }
    }
    
    /// Returns last logs synchronously (for safe reading at crash time)
    public func getLogs() -> String {
        return queue.sync {
            return logs.joined(separator: "\n")
        }
    }

    /// Returns last logs as a list (for cloud reporting)
    public func getLogEntries() -> [String] {
        return queue.sync {
            return logs
        }
    }
}

