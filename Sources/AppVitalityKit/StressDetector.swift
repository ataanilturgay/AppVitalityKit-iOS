import Foundation
import UIKit

/**
 * On-Device Stress Detector
 *
 * Calculates real-time user stress level (0-100) based on behavioral signals.
 * When stress is high, increases sampling rate to capture critical moments.
 *
 * Signals monitored:
 * - Rage taps (rapid taps)
 * - Dead clicks (taps with no response)
 * - FPS drops (UI stutters)
 * - Navigation loops (same screen revisits)
 * - Rapid back gestures
 *
 * Security: No user data leaves device, only aggregated scores
 * Performance: Lightweight rolling window, no persistent storage
 * Thread-safe: All operations are atomic
 */
public final class StressDetector {
    
    // MARK: - Singleton
    public static let shared = StressDetector()
    
    // MARK: - Configuration
    private struct Config {
        static let windowSeconds: TimeInterval = 30.0
        static let maxEvents = 100
        static let updateInterval: TimeInterval = 1.0
        
        // Weights for stress calculation (total = 1.0)
        static let weights = (
            rageTap: 0.30,
            deadClick: 0.25,
            fpsDrop: 0.20,
            navigationLoop: 0.15,
            backGesture: 0.10
        )
        
        // Thresholds per 30 seconds
        static let thresholds = (
            rageTapCritical: 5,
            deadClickCritical: 4,
            fpsDropCritical: 3,
            navigationLoopCritical: 3,
            backGestureCritical: 4
        )
        
        // Stress levels
        static let stressLevels = (
            calm: 0...20,
            low: 21...40,
            medium: 41...60,
            high: 61...80,
            critical: 81...100
        )
    }
    
    // MARK: - Types
    public enum StressLevel: String {
        case calm
        case low
        case medium
        case high
        case critical
    }
    
    private enum EventType {
        case rageTap
        case deadClick
        case fpsDrop
        case navigationLoop
        case backGesture
    }
    
    private struct StressEvent {
        let type: EventType
        let timestamp: Date
    }
    
    public struct StressState {
        public let score: Int
        public let level: StressLevel
        public let rageTapCount: Int
        public let deadClickCount: Int
        public let fpsDropCount: Int
        public let navigationLoopCount: Int
        public let backGestureCount: Int
        public let samplingMultiplier: Double
    }
    
    // MARK: - State (Thread-safe)
    private let queue = DispatchQueue(label: "io.appvitality.stress", qos: .utility)
    private var events: [StressEvent] = []
    private var currentScore: Int = 0
    private var currentLevel: StressLevel = .calm
    private var isEnabled = false
    private var updateTimer: Timer?
    
    // Navigation tracking
    private var recentScreens: [String] = []
    private let maxRecentScreens = 10
    
    // Callbacks
    private var onStressChange: ((StressState) -> Void)?
    
    // MARK: - Init
    private init() {}
    
    // MARK: - Public API
    
    /// Start stress detection
    public func start(onStressChange: ((StressState) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self, !self.isEnabled else { return }
            self.isEnabled = true
            self.onStressChange = onStressChange
            
            DispatchQueue.main.async {
                self.startUpdateTimer()
            }
            
            print("🧠 [StressDetector] Started monitoring")
        }
    }
    
    /// Stop stress detection
    public func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isEnabled = false
            self.events.removeAll()
            self.recentScreens.removeAll()
            
            DispatchQueue.main.async {
                self.updateTimer?.invalidate()
                self.updateTimer = nil
            }
            
            print("🧠 [StressDetector] Stopped")
        }
    }
    
    /// Get current stress state
    public func getCurrentState() -> StressState {
        var state: StressState!
        queue.sync {
            state = buildState()
        }
        return state
    }
    
    // MARK: - Event Recording (called from FrustrationDetector)
    
    internal func recordRageTap() {
        recordEvent(.rageTap)
    }
    
    internal func recordDeadClick() {
        recordEvent(.deadClick)
    }
    
    internal func recordFpsDrop() {
        recordEvent(.fpsDrop)
    }
    
    internal func recordBackGesture() {
        recordEvent(.backGesture)
    }
    
    internal func recordScreenView(_ screen: String) {
        queue.async { [weak self] in
            guard let self = self, self.isEnabled else { return }
            
            // Check for navigation loop (revisiting same screen quickly)
            if self.recentScreens.contains(screen) {
                self.recordEventSync(.navigationLoop)
            }
            
            self.recentScreens.append(screen)
            if self.recentScreens.count > self.maxRecentScreens {
                self.recentScreens.removeFirst()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func recordEvent(_ type: EventType) {
        queue.async { [weak self] in
            self?.recordEventSync(type)
        }
    }
    
    private func recordEventSync(_ type: EventType) {
        guard isEnabled else { return }
        
        let event = StressEvent(type: type, timestamp: Date())
        events.append(event)
        
        // Limit events to prevent memory issues
        if events.count > Config.maxEvents {
            events.removeFirst(events.count - Config.maxEvents)
        }
    }
    
    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: Config.updateInterval, repeats: true) { [weak self] _ in
            self?.updateStressScore()
        }
    }
    
    private func updateStressScore() {
        queue.async { [weak self] in
            guard let self = self, self.isEnabled else { return }
            
            // Clean old events
            let cutoff = Date().addingTimeInterval(-Config.windowSeconds)
            self.events.removeAll { $0.timestamp < cutoff }
            
            // Calculate score
            let state = self.buildState()
            let previousLevel = self.currentLevel
            
            self.currentScore = state.score
            self.currentLevel = state.level
            
            // Notify if level changed
            if state.level != previousLevel {
                DispatchQueue.main.async {
                    self.onStressChange?(state)
                    
                    // Report stress change event
                    AppVitalityKit.shared.handle(event: .stressLevelChange(
                        level: state.level.rawValue,
                        score: state.score,
                        multiplier: state.samplingMultiplier
                    ))
                }
                
                print("🧠 [StressDetector] Level changed: \(previousLevel.rawValue) → \(state.level.rawValue) (score: \(state.score))")
            }
        }
    }
    
    private func buildState() -> StressState {
        let counts = countEvents()
        let score = calculateScore(counts: counts)
        let level = getLevel(score: score)
        let multiplier = getSamplingMultiplier(level: level)
        
        return StressState(
            score: score,
            level: level,
            rageTapCount: counts.rageTap,
            deadClickCount: counts.deadClick,
            fpsDropCount: counts.fpsDrop,
            navigationLoopCount: counts.navigationLoop,
            backGestureCount: counts.backGesture,
            samplingMultiplier: multiplier
        )
    }
    
    private func countEvents() -> (rageTap: Int, deadClick: Int, fpsDrop: Int, navigationLoop: Int, backGesture: Int) {
        var rageTap = 0, deadClick = 0, fpsDrop = 0, navigationLoop = 0, backGesture = 0
        
        for event in events {
            switch event.type {
            case .rageTap: rageTap += 1
            case .deadClick: deadClick += 1
            case .fpsDrop: fpsDrop += 1
            case .navigationLoop: navigationLoop += 1
            case .backGesture: backGesture += 1
            }
        }
        
        return (rageTap, deadClick, fpsDrop, navigationLoop, backGesture)
    }
    
    private func calculateScore(counts: (rageTap: Int, deadClick: Int, fpsDrop: Int, navigationLoop: Int, backGesture: Int)) -> Int {
        // Normalize each signal (0-100 based on thresholds)
        let rageTapScore = min(100, counts.rageTap * 100 / Config.thresholds.rageTapCritical)
        let deadClickScore = min(100, counts.deadClick * 100 / Config.thresholds.deadClickCritical)
        let fpsDropScore = min(100, counts.fpsDrop * 100 / Config.thresholds.fpsDropCritical)
        let navigationLoopScore = min(100, counts.navigationLoop * 100 / Config.thresholds.navigationLoopCritical)
        let backGestureScore = min(100, counts.backGesture * 100 / Config.thresholds.backGestureCritical)
        
        // Weighted sum
        let weightedScore = 
            Double(rageTapScore) * Config.weights.rageTap +
            Double(deadClickScore) * Config.weights.deadClick +
            Double(fpsDropScore) * Config.weights.fpsDrop +
            Double(navigationLoopScore) * Config.weights.navigationLoop +
            Double(backGestureScore) * Config.weights.backGesture
        
        return min(100, max(0, Int(weightedScore)))
    }
    
    private func getLevel(score: Int) -> StressLevel {
        if Config.stressLevels.calm.contains(score) { return .calm }
        if Config.stressLevels.low.contains(score) { return .low }
        if Config.stressLevels.medium.contains(score) { return .medium }
        if Config.stressLevels.high.contains(score) { return .high }
        return .critical
    }
    
    /// Get sampling multiplier based on stress level
    /// Higher stress = more data collection
    private func getSamplingMultiplier(level: StressLevel) -> Double {
        switch level {
        case .calm: return 1.0
        case .low: return 1.2
        case .medium: return 1.5
        case .high: return 2.0
        case .critical: return 3.0
        }
    }
}

// MARK: - AppVitalityEvent Extension
extension AppVitalityEvent {
    static func stressLevelChange(level: String, score: Int, multiplier: Double) -> AppVitalityEvent {
        return AppVitalityEvent(
            type: "stress_level_change",
            payload: [
                "level": level,
                "score": score,
                "samplingMultiplier": multiplier
            ]
        )
    }
}

