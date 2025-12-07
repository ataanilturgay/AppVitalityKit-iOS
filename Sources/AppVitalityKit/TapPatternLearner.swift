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
    
    // MARK: - Storage (Memory only - no persistence, resets each session)
    
    /// In-memory tap patterns - cleared when app restarts
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
    }
    
    // MARK: - Initialization
    
    private init() {
        // No persistence - patterns start fresh each session
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
    
    /// Clear all learned patterns (for testing or manual reset)
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        patterns.removeAll()
        AppVitalityKit.shared.debugLog("🧠 TapPatternLearner: Reset all patterns")
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

