import Foundation
import UIKit

/**
 * Adaptive Sampling V2
 *
 * Intelligent event sampling based on multiple factors:
 * 1. Stress Level (from StressDetector)
 * 2. Screen Importance (critical screens always sampled)
 * 3. Device Health (battery, memory)
 * 4. Time of Day (peak hours)
 * 5. Event Type Priority
 *
 * Security: No user data used, only device state
 * Performance: Lightweight checks, cached values
 * Thread-safe: Atomic operations
 */
public final class AdaptiveSampler {
    
    // MARK: - Singleton
    public static let shared = AdaptiveSampler()
    
    // MARK: - Configuration
    public struct Config {
        /// Base sampling rate (0.0 - 1.0)
        public var baseRate: Double = 0.1
        
        /// Critical screens that always get sampled
        public var criticalScreens: Set<String> = [
            "checkout", "payment", "login", "signup", "register",
            "purchase", "cart", "order", "settings", "profile"
        ]
        
        /// Event types that always get sampled
        public var criticalEventTypes: Set<String> = [
            "crash", "error", "rage_tap", "dead_click",
            "purchase_completed", "login_success", "login_failed"
        ]
        
        /// Low battery threshold (0.0 - 1.0)
        public var lowBatteryThreshold: Float = 0.20
        
        /// Peak hours (24h format)
        public var peakHoursStart: Int = 9
        public var peakHoursEnd: Int = 21
        
        public init() {}
    }
    
    // MARK: - State
    private var config = Config()
    private var isEnabled = false
    private var cachedStressMultiplier: Double = 1.0
    private var cachedDeviceMultiplier: Double = 1.0
    private var cachedTimeMultiplier: Double = 1.0
    private var lastCacheUpdate: Date = .distantPast
    private let cacheInterval: TimeInterval = 5.0 // Update cache every 5s
    
    private let queue = DispatchQueue(label: "io.appvitality.sampler", qos: .utility)
    
    // MARK: - Init
    private init() {}
    
    // MARK: - Public API
    
    /// Configure the sampler
    public func configure(_ config: Config) {
        queue.async { [weak self] in
            self?.config = config
        }
    }
    
    /// Enable adaptive sampling
    public func enable() {
        queue.async { [weak self] in
            self?.isEnabled = true
            print("📊 [AdaptiveSampler] Enabled")
        }
    }
    
    /// Disable adaptive sampling (all events pass through)
    public func disable() {
        queue.async { [weak self] in
            self?.isEnabled = false
            print("📊 [AdaptiveSampler] Disabled")
        }
    }
    
    /// Check if an event should be sampled
    /// - Returns: true if event should be sent, false if dropped
    public func shouldSample(eventType: String, screen: String?) -> Bool {
        var result = true
        queue.sync {
            result = shouldSampleSync(eventType: eventType, screen: screen)
        }
        return result
    }
    
    /// Get current effective sampling rate
    public func getCurrentRate() -> Double {
        var rate: Double = 0
        queue.sync {
            rate = calculateEffectiveRate()
        }
        return rate
    }
    
    // MARK: - Private Methods
    
    private func shouldSampleSync(eventType: String, screen: String?) -> Bool {
        // If disabled, sample everything
        guard isEnabled else { return true }
        
        // Critical events always sampled
        if config.criticalEventTypes.contains(eventType) {
            return true
        }
        
        // Critical screens always sampled
        if let screen = screen?.lowercased() {
            for criticalScreen in config.criticalScreens {
                if screen.contains(criticalScreen) {
                    return true
                }
            }
        }
        
        // Calculate effective rate and sample
        let effectiveRate = calculateEffectiveRate()
        return Double.random(in: 0...1) < effectiveRate
    }
    
    private func calculateEffectiveRate() -> Double {
        updateCacheIfNeeded()
        
        let rate = config.baseRate *
            cachedStressMultiplier *
            cachedDeviceMultiplier *
            cachedTimeMultiplier
        
        // Clamp between 0.01 and 1.0
        return min(1.0, max(0.01, rate))
    }
    
    private func updateCacheIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastCacheUpdate) > cacheInterval else { return }
        
        lastCacheUpdate = now
        
        // Update stress multiplier from StressDetector
        cachedStressMultiplier = StressDetector.shared.getCurrentState().samplingMultiplier
        
        // Update device multiplier
        cachedDeviceMultiplier = calculateDeviceMultiplier()
        
        // Update time multiplier
        cachedTimeMultiplier = calculateTimeMultiplier()
    }
    
    private func calculateDeviceMultiplier() -> Double {
        var multiplier = 1.0
        
        // Check battery level
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState
        
        if batteryLevel >= 0 && batteryLevel < config.lowBatteryThreshold && batteryState != .charging {
            // Low battery, reduce sampling
            multiplier *= 0.5
        }
        
        // Check memory pressure (simplified)
        let memoryInfo = ProcessInfo.processInfo.physicalMemory
        let usedMemory = getUsedMemory()
        let memoryUsagePercent = Double(usedMemory) / Double(memoryInfo)
        
        if memoryUsagePercent > 0.8 {
            // High memory usage, reduce sampling
            multiplier *= 0.7
        }
        
        return multiplier
    }
    
    private func calculateTimeMultiplier() -> Double {
        let hour = Calendar.current.component(.hour, from: Date())
        
        // Peak hours get higher sampling
        if hour >= config.peakHoursStart && hour < config.peakHoursEnd {
            return 1.2
        }
        
        // Off-peak hours get lower sampling
        return 0.8
    }
    
    private func getUsedMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return info.resident_size
        }
        return 0
    }
}

// MARK: - Convenience Extension
extension AdaptiveSampler {
    /// Quick check with just event type
    public func shouldSample(eventType: String) -> Bool {
        return shouldSample(eventType: eventType, screen: nil)
    }
}

