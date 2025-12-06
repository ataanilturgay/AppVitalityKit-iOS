import Foundation

/// "Black Box" that keeps user's last actions (breadcrumbs) in RAM and disk.
/// These steps are included in the report at crash time.
public class BreadcrumbLogger {
    
    public static let shared = BreadcrumbLogger()
    
    private var logs: [String] = []
    private let maxLogs = 50
    private let queue = DispatchQueue(label: "com.appvitality.breadcrumbs", qos: .utility)
    
    // Disk persistence
    private var fileHandle: FileHandle?
    private var filePath: URL?
    private let maxFileSize: UInt64 = 50 * 1024 // 50 KB max
    
    // Throttling for disk writes
    private var lastDiskWriteTime: Date = .distantPast
    private var pendingDiskWrite = false
    private let minDiskWriteInterval: TimeInterval = 0.5 // Max 2 writes per second
    
    private init() {
        setupPersistentFile()
        loadFromDisk()
    }
    
    deinit {
        fileHandle?.closeFile()
    }
    
    // MARK: - Setup
    
    private func setupPersistentFile() {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        
        let dir = cacheDir.appendingPathComponent("AppVitality")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        filePath = dir.appendingPathComponent("breadcrumbs.log")
        
        guard let path = filePath else { return }
        
        // Create file if not exists
        if !FileManager.default.fileExists(atPath: path.path) {
            FileManager.default.createFile(atPath: path.path, contents: nil)
        }
        
        // Open file handle for appending
        fileHandle = try? FileHandle(forWritingTo: path)
        fileHandle?.seekToEndOfFile()
    }
    
    private func loadFromDisk() {
        guard let path = filePath,
              let content = try? String(contentsOf: path, encoding: .utf8) else {
            return
        }
        
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        logs = Array(lines.suffix(maxLogs))
    }
    
    // MARK: - Public API
    
    /// Records an event or screen transition.
    /// - Parameter message: e.g. "Login button tapped", "HomeView appeared".
    public func log(_ message: String) {
        queue.async { [weak self] in
            self?.addLog(message, critical: false)
        }
    }
    
    /// Records a critical event and immediately persists to disk.
    /// Use for important user actions like button taps, navigation, API calls.
    /// - Parameter message: e.g. "Purchase button tapped", "Payment started".
    public func logCritical(_ message: String) {
        queue.async { [weak self] in
            self?.addLog(message, critical: true)
        }
    }
    
    /// Records a screen transition (always persisted immediately).
    /// - Parameter screenName: Name of the screen.
    public func logScreenView(_ screenName: String) {
        queue.async { [weak self] in
            self?.addLog("📱 Screen: \(screenName)", critical: true)
        }
    }
    
    /// Records a user action (persisted with throttling).
    /// - Parameters:
    ///   - action: Action name (e.g. "tap", "swipe").
    ///   - target: Target identifier or description.
    public func logAction(_ action: String, target: String) {
        queue.async { [weak self] in
            self?.addLog("👆 \(action): \(target)", critical: false)
        }
    }
    
    /// Records a network request.
    /// - Parameters:
    ///   - method: HTTP method.
    ///   - url: Request URL.
    public func logNetwork(_ method: String, url: String) {
        queue.async { [weak self] in
            // Truncate long URLs
            let shortURL = url.count > 80 ? String(url.prefix(77)) + "..." : url
            self?.addLog("🌐 \(method): \(shortURL)", critical: false)
        }
    }
    
    /// Records an error (always persisted immediately).
    /// - Parameters:
    ///   - error: Error description.
    ///   - context: Optional context.
    public func logError(_ error: String, context: String? = nil) {
        queue.async { [weak self] in
            var message = "❌ Error: \(error)"
            if let ctx = context {
                message += " | Context: \(ctx)"
            }
            self?.addLog(message, critical: true)
        }
    }
    
    /// Force flush all pending logs to disk.
    /// Call this before known risky operations.
    public func flush() {
        queue.async { [weak self] in
            self?.writeToDiskNow()
        }
    }
    
    /// Returns last logs synchronously (for safe reading at crash time).
    public func getLogs() -> String {
        return queue.sync {
            return logs.joined(separator: "\n")
        }
    }

    /// Returns last logs as a list (for cloud reporting).
    public func getLogEntries() -> [String] {
        return queue.sync {
            return logs
        }
    }
    
    /// Clear all logs (for testing or privacy).
    public func clear() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.logs.removeAll()
            self.truncateFile()
        }
    }
    
    // MARK: - Internal
    
    private func addLog(_ message: String, critical: Bool) {
        let timestamp = Self.timestampFormatter.string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        
        logs.append(entry)
        
        // Keep only last N logs
        if logs.count > maxLogs {
            logs.removeFirst()
        }
        
        // Persist to disk
        if critical {
            // Critical logs: write immediately
            writeToDiskNow()
        } else {
            // Normal logs: throttled write
            scheduleThrottledWrite()
        }
    }
    
    private func scheduleThrottledWrite() {
        guard !pendingDiskWrite else { return }
        
        let timeSinceLastWrite = Date().timeIntervalSince(lastDiskWriteTime)
        
        if timeSinceLastWrite >= minDiskWriteInterval {
            writeToDiskNow()
        } else {
            // Schedule delayed write
            pendingDiskWrite = true
            let delay = minDiskWriteInterval - timeSinceLastWrite
            
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.pendingDiskWrite = false
                self?.writeToDiskNow()
            }
        }
    }
    
    private func writeToDiskNow() {
        lastDiskWriteTime = Date()
        
        guard let path = filePath else { return }
        
        // Check file size and rotate if needed
        rotateFileIfNeeded()
        
        // Write all logs (overwrite mode for simplicity and reliability)
        let content = logs.joined(separator: "\n")
        try? content.write(to: path, atomically: true, encoding: .utf8)
    }
    
    private func rotateFileIfNeeded() {
        guard let path = filePath else { return }
        
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
            let fileSize = attrs[.size] as? UInt64 ?? 0
            
            if fileSize > maxFileSize {
                // Keep only last 25 entries when rotating
                logs = Array(logs.suffix(25))
            }
        } catch {
            // Ignore
        }
    }
    
    private func truncateFile() {
        guard let path = filePath else { return }
        try? "".write(to: path, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Timestamp Formatter
    
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

// MARK: - Convenience Extensions

public extension BreadcrumbLogger {
    
    /// Log with automatic categorization based on prefix.
    /// - Parameters:
    ///   - category: Category emoji (e.g. "🔐" for auth, "💰" for payment).
    ///   - message: Log message.
    ///   - critical: Whether to persist immediately.
    func log(category: String, _ message: String, critical: Bool = false) {
        queue.async { [weak self] in
            self?.addLog("\(category) \(message)", critical: critical)
        }
    }
}
