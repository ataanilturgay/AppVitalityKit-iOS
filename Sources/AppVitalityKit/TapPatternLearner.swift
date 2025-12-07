import Foundation
import UIKit

/// Auto-learning system for detecting misleading UI elements.
/// Tracks tap patterns on non-interactive views and learns which ones
/// users frequently try to tap (indicating they look clickable).
///
/// This is a self-learning system that requires no developer configuration.
/// The SDK learns from real user behavior which elements are confusing.
public final class TapPatternLearner {
    
    public static let shared = TapPatternLearner()
    
    // MARK: - Configuration
    
    /// Number of taps required before a view is considered "learned clickable"
    private let learningThreshold = 5
    
    /// Time window for counting taps (older taps decay)
    private let decayWindow: TimeInterval = 86400 * 7 // 7 days
    
    /// Maximum patterns to store locally
    private let maxPatterns = 100
    
    // MARK: - Storage
    
    /// Key for UserDefaults storage
    private let storageKey = "appvitality_tap_patterns"
    
    /// In-memory cache of tap patterns
    private var patterns: [String: TapPattern] = [:]
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - Types

    public struct TapPattern: Codable {
        public let viewType: String
        public let screen: String
        public let viewId: String?
        public internal(set) var tapCount: Int
        public internal(set) var lastTapDate: Date
        public internal(set) var isLearnedClickable: Bool

        public var key: String {
            return "\(screen):\(viewType):\(viewId ?? "nil")"
        }

        /// Check if pattern has decayed (old data)
        public func isDecayed(window: TimeInterval) -> Bool {
            return Date().timeIntervalSince(lastTapDate) > window
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        loadPatterns()
    }
    
    // MARK: - Public API
    
    /// Record a tap on a non-interactive view.
    /// Called for EVERY non-interactive tap, not just dead clicks.
    /// The system learns over time which views are frequently tapped.
    ///
    /// - Parameters:
    ///   - viewType: The type of the view (e.g., "UILabel", "UIImageView")
    ///   - screen: The screen where the tap occurred
    ///   - viewId: Optional accessibility identifier
    /// - Returns: True if this view has been learned as clickable-looking
    @discardableResult
    public func recordTap(viewType: String, screen: String?, viewId: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let screenName = screen ?? "Unknown"
        let key = "\(screenName):\(viewType):\(viewId ?? "nil")"
        
        if var pattern = patterns[key] {
            // Existing pattern - increment tap count
            pattern.tapCount += 1
            pattern.lastTapDate = Date()
            
            // Check if it crossed the threshold
            if !pattern.isLearnedClickable && pattern.tapCount >= learningThreshold {
                pattern.isLearnedClickable = true
                AppVitalityKit.shared.debugLog("🧠 TapPatternLearner: Learned new clickable-looking element: \(viewType) on \(screenName) (after \(pattern.tapCount) taps)")
                
                // Send learning event to backend
                sendLearningEvent(pattern: pattern)
            }
            
            patterns[key] = pattern
        } else {
            // New pattern
            let pattern = TapPattern(
                viewType: viewType,
                screen: screenName,
                viewId: viewId,
                tapCount: 1,
                lastTapDate: Date(),
                isLearnedClickable: false
            )
            patterns[key] = pattern
        }
        
        // Persist periodically (every 10 taps)
        let totalTaps = patterns.values.reduce(0) { $0 + $1.tapCount }
        if totalTaps % 10 == 0 {
            savePatterns()
        }
        
        return patterns[key]?.isLearnedClickable ?? false
    }
    
    /// Check if a view has been learned as clickable-looking
    ///
    /// - Parameters:
    ///   - viewType: The type of the view
    ///   - screen: The screen name
    ///   - viewId: Optional accessibility identifier
    /// - Returns: True if users frequently tap this view
    public func isLearnedClickable(viewType: String, screen: String?, viewId: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let screenName = screen ?? "Unknown"
        let key = "\(screenName):\(viewType):\(viewId ?? "nil")"
        
        return patterns[key]?.isLearnedClickable ?? false
    }
    
    /// Get all learned patterns (for syncing to backend)
    public func getLearnedPatterns() -> [TapPattern] {
        lock.lock()
        defer { lock.unlock() }
        
        return patterns.values.filter { $0.isLearnedClickable }
    }
    
    /// Get tap statistics for a specific view
    public func getTapCount(viewType: String, screen: String?, viewId: String?) -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        let screenName = screen ?? "Unknown"
        let key = "\(screenName):\(viewType):\(viewId ?? "nil")"
        
        return patterns[key]?.tapCount ?? 0
    }
    
    /// Clear all learned patterns (for testing)
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        patterns.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
        AppVitalityKit.shared.debugLog("🧠 TapPatternLearner: Reset all patterns")
    }
    
    // MARK: - Persistence
    
    private func loadPatterns() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: TapPattern].self, from: data) else {
            return
        }
        
        // Filter out decayed patterns
        patterns = decoded.filter { !$0.value.isDecayed(window: decayWindow) }
        
        let learnedCount = patterns.values.filter { $0.isLearnedClickable }.count
        if learnedCount > 0 {
            AppVitalityKit.shared.debugLog("🧠 TapPatternLearner: Loaded \(patterns.count) patterns (\(learnedCount) learned)")
        }
    }
    
    private func savePatterns() {
        // Limit stored patterns
        if patterns.count > maxPatterns {
            // Remove oldest, non-learned patterns first
            let sortedKeys = patterns.keys.sorted { key1, key2 in
                let p1 = patterns[key1]!
                let p2 = patterns[key2]!
                
                // Keep learned patterns
                if p1.isLearnedClickable != p2.isLearnedClickable {
                    return p1.isLearnedClickable
                }
                
                // Keep more recent patterns
                return p1.lastTapDate > p2.lastTapDate
            }
            
            let keysToKeep = Set(sortedKeys.prefix(maxPatterns))
            patterns = patterns.filter { keysToKeep.contains($0.key) }
        }
        
        guard let data = try? JSONEncoder().encode(patterns) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    // MARK: - Backend Sync
    
    private func sendLearningEvent(pattern: TapPattern) {
        // Send a special event to track learned patterns
        let event = AppVitalityEvent.custom(name: "tap_pattern_learned", parameters: [
            "view_type": AnyEncodable(pattern.viewType),
            "screen": AnyEncodable(pattern.screen),
            "view_id": AnyEncodable(pattern.viewId ?? ""),
            "tap_count": AnyEncodable(pattern.tapCount),
            "threshold": AnyEncodable(learningThreshold)
        ])
        AppVitalityKit.shared.handle(event: event)
    }
    
    /// Sync all learned patterns to backend (called periodically)
    public func syncToBackend() {
        let learned = getLearnedPatterns()
        guard !learned.isEmpty else { return }
        
        AppVitalityKit.shared.debugLog("🧠 TapPatternLearner: Syncing \(learned.count) learned patterns to backend")
        
        // Send as a batch event
        let patternsData = learned.map { pattern -> [String: AnyEncodable] in
            return [
                "view_type": AnyEncodable(pattern.viewType),
                "screen": AnyEncodable(pattern.screen),
                "view_id": AnyEncodable(pattern.viewId ?? ""),
                "tap_count": AnyEncodable(pattern.tapCount)
            ]
        }
        
        let event = AppVitalityEvent.custom(name: "tap_patterns_sync", parameters: [
            "patterns": AnyEncodable(patternsData),
            "count": AnyEncodable(learned.count)
        ])
        AppVitalityKit.shared.handle(event: event)
    }
}

