import Foundation
import UIKit

public class AppVitalityKit {

    public static let shared = AppVitalityKit()

    /// Delegate for exporting data externally.
    /// Developers can set this to send data (Crash, FPS, CPU) to their own backend.
    public weak var delegate: AppVitalityDelegate?

    // MARK: - Feature Enum
    
    /// Features that SDK can monitor automatically.
    public enum Feature {
        case metricKitReporting   // Collect energy and performance reports
        case networkMonitoring    // Monitor URLSession traffic and warn (does NOT block)
        case mainThreadWatchdog   // Catch UI hangs
        case memoryMonitor        // Warn about excessive RAM usage
        case crashReporting       // Record basic crash reasons
        case fpsMonitor           // Monitor UI smoothness (Frame Drop)
        case cpuMonitor           // Monitor CPU usage and thermal state
        case autoActionTracking   // Automatic UI Tracking (Taps, Screen Transitions)
        case frustrationDetection // Detect rage taps and dead clicks (UX issues)
        
        /// All available features
        public static let all: Set<Feature> = [
            .metricKitReporting,
            .networkMonitoring,
            .mainThreadWatchdog,
            .memoryMonitor,
            .crashReporting,
            .fpsMonitor,
            .cpuMonitor,
            .autoActionTracking,
            .frustrationDetection
        ]
        
        /// Recommended features for most apps
        public static let recommended: Set<Feature> = [
            .fpsMonitor,
            .cpuMonitor,
            .crashReporting,
            .autoActionTracking,
            .frustrationDetection
        ]
    }

    // MARK: - Options
    
    /// Configuration options for SDK behavior.
    ///
    /// ## Quick Start (Default - Small Apps)
    /// ```swift
    /// AppVitalityKit.shared.configure(apiKey: "your-key")
    /// ```
    ///
    /// ## High-Traffic Apps (>100K DAU)
    /// ```swift
    /// AppVitalityKit.shared.configure(
    ///     apiKey: "your-key",
    ///     options: Options(
    ///         flushInterval: 30,      // Send every 30 seconds
    ///         eventSampleRate: 0.5    // Send 50% of events
    ///     )
    /// )
    /// ```
    ///
    /// ## Enterprise Apps (>1M DAU)
    /// ```swift
    /// AppVitalityKit.shared.configure(apiKey: "your-key", options: .enterprise)
    /// ```
    public struct Options {
        
        /// Battery and performance impact level.
        /// - `strict`: Maximum monitoring, higher battery usage
        /// - `moderate`: Balanced (recommended)
        /// - `relaxed`: Minimal impact, less frequent monitoring
        public enum PowerPolicy {
            case strict
            case moderate
            case relaxed
        }
        
        /// Which features to enable.
        /// Default: `.recommended` (crash reporting, auto-tracking, frustration detection)
        public var features: Set<Feature>
        
        /// Battery/performance impact policy.
        /// Default: `.moderate`
        public var policy: PowerPolicy
        
        /// How often to send batched events to server (in seconds).
        ///
        /// **Recommendations:**
        /// - Small apps (<10K DAU): `10` seconds (default)
        /// - Medium apps (10K-100K DAU): `30` seconds
        /// - Large apps (>100K DAU): `60` seconds
        ///
        /// Lower values = more real-time data, higher battery usage.
        /// Default: `10`
        public var flushInterval: TimeInterval
        
        /// Maximum events to send in a single network request.
        ///
        /// **Recommendations:**
        /// - Default: `20` (good balance)
        /// - High-traffic: `50-100` (reduces network requests)
        ///
        /// Default: `20`
        public var maxBatchSize: Int
        
        /// Custom API endpoint URL.
        /// Leave `nil` to use AppVitality cloud (https://api.appvitality.io).
        /// Only set this for on-premise deployments.
        public var customEndpoint: URL?

        /// Enable verbose debug logging in Xcode console.
        /// Useful for debugging SDK integration. Disable in production.
        /// Default: `false`
        public var enableDebugLogging: Bool
        
        /// Percentage of events to send (0.0 to 1.0).
        ///
        /// Default is 10% for cost efficiency. Adaptive sampling automatically
        /// increases to 100% when problems are detected (rage taps, errors, etc.)
        ///
        /// Override examples:
        /// - `0.1` = 10% (default, cost efficient)
        /// - `0.5` = 50% (more data, higher cost)
        /// - `1.0` = 100% (all events, highest cost)
        ///
        /// **Important:** Crashes, rage taps, critical paths are ALWAYS sent (100%).
        ///
        /// Default: `0.1` (10%)
        public var eventSampleRate: Double
        
        /// Maximum events to queue in memory before dropping oldest.
        ///
        /// Prevents memory issues on high-traffic apps. When queue is full,
        /// oldest events are dropped to make room for new ones.
        ///
        /// **Recommendations:**
        /// - Default: `500` (~50KB memory)
        /// - High-traffic: `1000` (~100KB memory)
        ///
        /// Default: `500`
        public var maxQueueSize: Int
        
        /// Create custom options (most developers don't need this).
        /// The SDK auto-tunes itself based on device conditions.
        public init(
            features: Set<Feature> = Feature.recommended,
            policy: PowerPolicy = .moderate,
            flushInterval: TimeInterval = 10,
            maxBatchSize: Int = 20,
            customEndpoint: URL? = nil,
            enableDebugLogging: Bool = false,
            eventSampleRate: Double = 0.1,
            maxQueueSize: Int = 500
        ) {
            self.features = features
            self.policy = policy
            self.flushInterval = flushInterval
            self.maxBatchSize = maxBatchSize
            self.customEndpoint = customEndpoint
            self.enableDebugLogging = enableDebugLogging
            self.eventSampleRate = max(0.0, min(1.0, eventSampleRate))
            self.maxQueueSize = max(10, maxQueueSize)
        }
        
        /// Default auto-tuned options. SDK automatically adjusts based on:
        /// - Device memory (low memory = more aggressive sampling)
        /// - Battery state (low battery = less frequent uploads)
        /// - Thermal state (hot device = reduced monitoring)
        public static var automatic: Options {
            var options = Options()
            
            // Auto-tune based on device memory
            let totalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
            if totalMemoryGB < 2 {
                // Low-end device: be more conservative
                options.eventSampleRate = 0.5
                options.maxQueueSize = 200
                options.flushInterval = 30
            } else if totalMemoryGB < 4 {
                // Mid-range device
                options.eventSampleRate = 0.8
                options.maxQueueSize = 500
                options.flushInterval = 15
            }
            // High-end devices use defaults (full tracking)
            
            return options
        }
        
        /// All features enabled. Use for development/testing.
        public static var allFeatures: Options {
            Options(features: Feature.all)
        }
        
        /// Optimized for high-traffic apps (>1M DAU).
        public static var enterprise: Options {
            Options(
                features: Feature.recommended,
                policy: .relaxed,
                flushInterval: 60,
                maxBatchSize: 50,
                eventSampleRate: 0.1,
                maxQueueSize: 1000
            )
        }
    }
    
    // MARK: - Internal Types
    
    /// Default API endpoint (base URL, paths appended by uploader)
    public static let defaultEndpoint = URL(string: "https://api.appvitality.io")!

    private var isConfigured = false
    private var apiKey: String?
    private var options: Options?
    private var uploader: AppVitalityUploader?
    private var sessionStartTime: Date?
    
    // MARK: - Adaptive Sampling (Activity-Based)

    /// Tracks recent user interactions for adaptive sampling
    private var recentInteractionTimestamps: [Date] = []
    private let interactionWindow: TimeInterval = 60 // 1 minute window
    private let highActivityThreshold = 30 // >30 interactions/min = high activity
    private let lowActivityThreshold = 5   // <5 interactions/min = low activity
    private var currentActivityMultiplier: Double = 1.0
    private var activityCheckTimer: Timer?

    // MARK: - User Risk Score

    /// Current user risk score (0-100)
    /// Higher score = more problems detected = higher sampling priority
    private var currentRiskScore: Int = 0

    /// Risk signal tracking (sliding window)
    private var recentRageTaps: [Date] = []
    private var recentDeadClicks: [Date] = []
    private var recentErrors: [Date] = []
    private var recentUIHangs: [Date] = []
    private var recentHTTPErrors: [Date] = []
    private let riskWindow: TimeInterval = 300 // 5 minute window

    /// Previous session had a crash
    private var hadCrashInPreviousSession: Bool = false

    /// Risk score thresholds
    private let highRiskThreshold = 70  // Above this = full sampling
    private let mediumRiskThreshold = 40

    // MARK: - Critical Path Detection
    
    /// Current screen name for critical path detection
    private var currentScreenName: String?
    
    /// Whether current screen is on critical path
    private var isOnCriticalPath: Bool = false
    
    /// Critical screens defined by developer (no auto-detection)
    /// Developer knows which screens are truly business-critical
    private var criticalScreens: Set<String> = []

    private init() {
        // Setup session tracking
        setupSessionTracking()
    }
    
    private func setupSessionTracking() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }
    
    @objc private func appDidBecomeActive() {
        guard isConfigured else { return }
        sessionStartTime = Date()
        handle(event: .sessionStart)
    }
    
    @objc private func appWillResignActive() {
        guard isConfigured, let startTime = sessionStartTime else { return }
        let duration = Date().timeIntervalSince(startTime)
        handle(event: .sessionEnd(duration: duration))
        sessionStartTime = nil
    }

    // MARK: - Configure
    
    /// Initialize AppVitalityKit with your API key.
    /// SDK automatically optimizes settings based on device conditions.
    ///
    /// ```swift
    /// // That's it! SDK auto-tunes everything.
    /// AppVitalityKit.shared.configure(apiKey: "your-api-key")
    /// ```
    ///
    /// - Parameter apiKey: Your project API key from AppVitality Dashboard
    public func configure(apiKey: String) {
        configure(apiKey: apiKey, options: .automatic)
    }
    
    /// Initialize AppVitalityKit with custom options (advanced usage).
    /// Most developers should use `configure(apiKey:)` instead.
    public func configure(apiKey: String, options: Options) {
        guard !isConfigured else {
            print("⚠️ AppVitalityKit is already configured.")
            return
        }

        self.apiKey = apiKey
        
        // Apply runtime auto-tuning on top of provided options
        var tunedOptions = options
        applyRuntimeTuning(&tunedOptions)
        
        self.options = tunedOptions
        self.isConfigured = true
        
        debugLog("Configuring with endpoint: \(tunedOptions.customEndpoint?.absoluteString ?? Self.defaultEndpoint.absoluteString)")
        let featureList = tunedOptions.features.map { "\($0)" }.joined(separator: ",")
        debugLog("Features: \(featureList)")
        debugLog("Auto-tuned: sampleRate=\(tunedOptions.eventSampleRate), flushInterval=\(tunedOptions.flushInterval)s")

        // Setup cloud uploader (this loads and sends pending crashes with their breadcrumbs)
        let endpoint = tunedOptions.customEndpoint ?? Self.defaultEndpoint
        let uploaderConfig = AppVitalityUploader.CloudConfig(
            endpoint: endpoint,
            apiKey: apiKey,
            flushInterval: tunedOptions.flushInterval,
            maxBatchSize: tunedOptions.maxBatchSize,
            maxQueueSize: tunedOptions.maxQueueSize
        )
        self.uploader = AppVitalityUploader(config: uploaderConfig)
        
        // Clear breadcrumbs AFTER uploader processes pending crashes
        // This ensures crash reports include breadcrumbs from the crashed session
        BreadcrumbLogger.shared.clear()

        print("🔋 AppVitalityKit is starting...")

        // 1. MetricKit
        if tunedOptions.features.contains(.metricKitReporting) {
            if #available(iOS 13.0, *) {
                _ = MetricKitCollector.shared
            }
        }

        // 2. Network Monitoring
        if tunedOptions.features.contains(.networkMonitoring) {
            URLProtocol.registerClass(AppVitalityNetworkMonitor.self)
            AppVitalityNetworkMonitor.configuration.blockRequestsInLowPowerMode = (tunedOptions.policy == .strict)
            AppVitalityNetworkMonitor.configuration.blockRequestsInBackground = false
            AppVitalityNetworkMonitor.configuration.verboseLogging = true
        }

        // 3. Watchdog (UI Hangs)
        if tunedOptions.features.contains(.mainThreadWatchdog) {
            MainThreadWatchdog.shared.start()
        }

        // 4. Memory Monitor
        if tunedOptions.features.contains(.memoryMonitor) {
            MemoryMonitor.shared.start()
        }

        // 5. Crash Reporter
        if tunedOptions.features.contains(.crashReporting) {
            SimpleCrashReporter.start()
        }

        // 6. FPS Monitor
        if tunedOptions.features.contains(.fpsMonitor) {
            FPSMonitor.shared.start()
        }

        // 7. CPU Monitor
        if tunedOptions.features.contains(.cpuMonitor) {
            CPUMonitor.shared.start()
        }

        // 8. Auto Action Tracking
        if tunedOptions.features.contains(.autoActionTracking) {
            UIViewController.enableLifecycleTracking()
            UIControl.enableActionTracking()
        }

        // 9. Frustration Detection (Rage Taps & Dead Clicks)
        if tunedOptions.features.contains(.frustrationDetection) {
            _ = FrustrationDetector.shared
        }
        
        // 10. Start Adaptive Sampling (Activity-Based)
        startActivityMonitor()

        // 11. Check for previous crash (affects risk score)
        checkPreviousCrash()

        print("🚀 AppVitalityKit is ready. (\(tunedOptions.features.count) features enabled)")
    }
    
    // MARK: - Runtime Auto-Tuning
    
    /// Automatically adjusts SDK settings based on current device conditions.
    /// Called once at startup and doesn't change during runtime.
    private func applyRuntimeTuning(_ options: inout Options) {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        
        // 1. Low battery → reduce upload frequency
        if device.batteryState != .charging && device.batteryLevel < 0.2 && device.batteryLevel > 0 {
            options.flushInterval = max(options.flushInterval, 60)
            debugLog("Auto-tune: Low battery, flushInterval=\(options.flushInterval)s")
        }
        
        // 2. Low Power Mode → reduce sampling
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            options.eventSampleRate = min(options.eventSampleRate, 0.5)
            options.flushInterval = max(options.flushInterval, 30)
            debugLog("Auto-tune: Low Power Mode, sampleRate=\(options.eventSampleRate)")
        }
        
        // 3. Thermal state → reduce monitoring
        let thermalState = ProcessInfo.processInfo.thermalState
        if thermalState == .serious || thermalState == .critical {
            options.eventSampleRate = min(options.eventSampleRate, 0.3)
            // Disable heavy monitors on hot devices
            options.features.remove(.fpsMonitor)
            options.features.remove(.cpuMonitor)
            debugLog("Auto-tune: Device is hot, reduced monitoring")
        }
        
        // 4. Low memory device → smaller queue
        let totalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        if totalMemoryGB < 2 {
            options.maxQueueSize = min(options.maxQueueSize, 200)
            debugLog("Auto-tune: Low memory device, maxQueueSize=\(options.maxQueueSize)")
        }
    }
    
    // MARK: - Manual Logging
    
    /// Log a custom event to AppVitality
    /// - Parameters:
    ///   - name: Name of the event (e.g., "user_purchase")
    ///   - parameters: Additional data (optional)
    public func log(event name: String, parameters: [String: AnyEncodable] = [:]) {
        let event = AppVitalityEvent.custom(name: name, parameters: parameters)
        handle(event: event)
    }
    
    /// Log a custom event with Any parameters (convenience overload)
    /// - Parameters:
    ///   - name: Name of the event (e.g., "user_purchase")
    ///   - parameters: Dictionary with any values (will be wrapped in AnyEncodable)
    public func log(event name: String, parameters: [String: Any]) {
        let wrapped = parameters.mapValues { AnyEncodable($0) }
        log(event: name, parameters: wrapped)
    }
    
    /// Log a custom event with an Encodable object
    /// - Parameters:
    ///   - name: Name of the event (e.g., "user_purchase")
    ///   - object: Any Encodable object (will be converted to dictionary)
    public func log<T: Encodable>(event name: String, object: T) {
        do {
            let data = try JSONEncoder().encode(object)
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                log(event: name, parameters: dict)
            } else {
                log(event: name, parameters: ["value": AnyEncodable(String(describing: object))])
            }
        } catch {
            log(event: name, parameters: ["value": AnyEncodable(String(describing: object))])
        }
    }
    
    // MARK: - Critical Path API
    
    /// Mark specific screens as critical for enhanced tracking.
    /// Critical screens get: 100% sampling, detailed breadcrumbs, full performance monitoring.
    ///
    /// Only YOU know which screens are truly business-critical.
    /// A user viewing cart 500 times is normal, but abandoning at payment confirmation is critical.
    ///
    /// ```swift
    /// // Mark ONLY the screens where user intent is clear
    /// AppVitalityKit.shared.markCriticalScreens([
    ///     "PaymentConfirmViewController",  // User is about to pay
    ///     "CheckoutFinalViewController",   // Final checkout step
    ///     "SubscriptionPurchaseVC"         // Subscription purchase
    /// ])
    /// ```
    ///
    /// NOT recommended as critical:
    /// - CartViewController (users browse cart casually)
    /// - LoginViewController (users might just be checking)
    /// - ProductDetailVC (browsing, not buying)
    public func markCriticalScreens(_ screenNames: [String]) {
        criticalScreens = Set(screenNames.map { $0.lowercased() })
        debugLog("Critical screens marked: \(screenNames)")
    }
    
    /// Add a single screen to critical path
    public func addCriticalScreen(_ screenName: String) {
        criticalScreens.insert(screenName.lowercased())
        debugLog("Added critical screen: \(screenName)")
    }
    
    /// Remove a screen from critical path
    public func removeCriticalScreen(_ screenName: String) {
        criticalScreens.remove(screenName.lowercased())
        debugLog("Removed critical screen: \(screenName)")
    }
    
    /// Clear all critical screens
    public func clearCriticalScreens() {
        criticalScreens.removeAll()
        debugLog("Cleared all critical screens")
    }
    
    /// Check if a screen is on critical path
    public func isCriticalScreen(_ screenName: String) -> Bool {
        return criticalScreens.contains(screenName.lowercased())
    }
    
    /// Called internally when screen changes (from UIViewController tracking)
    internal func onScreenChanged(_ screenName: String) {
        currentScreenName = screenName
        let wasCritical = isOnCriticalPath
        isOnCriticalPath = criticalScreens.contains(screenName.lowercased())
        
        if isOnCriticalPath && !wasCritical {
            debugLog("🎯 Entered critical path: \(screenName) - Enhanced tracking enabled")
            BreadcrumbLogger.shared.logCritical("Entered critical screen: \(screenName)")
        } else if !isOnCriticalPath && wasCritical {
            debugLog("📤 Left critical path: \(screenName) - Normal tracking resumed")
        }
    }
    
    /// Report a crash before calling fatalError
    /// This ensures the crash is saved to disk before the app terminates
    /// - Parameters:
    ///   - message: Crash message/reason
    ///   - file: Source file (defaults to #file)
    ///   - line: Source line (defaults to #line)
    /// - Example:
    ///   ```
    ///   AppVitalityKit.shared.reportCrash(message: "Test crash")
    ///   fatalError("Test crash")
    ///   ```
    public func reportCrash(message: String, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let stackTrace = Thread.callStackSymbols.joined(separator: "\n")
        let crashLog = """
        [CRASH REPORT - FATAL ERROR]
        Date: \(Date())
        Message: \(message)
        File: \(fileName):\(line)
        
        [STACK TRACE]
        \(stackTrace)
        """
        
        let report = AppVitalityCrashReport(
            title: "FatalError",
            reason: message,
            stackTrace: stackTrace,
            logString: crashLog,
            observedAt: Date(),
            breadcrumbs: BreadcrumbLogger.shared.getLogEntries().map { ["message": AnyEncodable($0)] },
            environment: nil
        )
        
        // Use sync handler to ensure disk write before fatalError
        handleCrashSync(report: report)
    }

    /// Access to current options (Read-only)
    public var currentOptions: Options? {
        return options
    }

    // MARK: - Internal Event Handling

    func handle(event: AppVitalityEvent) {
        // Track user interactions for adaptive sampling
        if isUserInteractionEvent(event.type) {
            trackInteraction()
        }

        // Track risk signals for risk-based sampling
        if isRiskSignalEvent(event.type) {
            trackRiskSignal(type: event.type)
        }

        // Calculate effective sample rate (risk score overrides activity level)
        let effectiveSampleRate = getEffectiveSampleRate()

        // Build SDK metadata for analytics
        let sdkMetadata: [String: AnyEncodable] = [
            "_sdk_critical_path": AnyEncodable(isOnCriticalPath),
            "_sdk_sample_rate": AnyEncodable(effectiveSampleRate),
            "_sdk_activity_multiplier": AnyEncodable(currentActivityMultiplier),
            "_sdk_risk_score": AnyEncodable(currentRiskScore),
            "_sdk_screen": AnyEncodable(currentScreenName ?? "unknown")
        ]

        // Critical Path: Always 100% sampling on critical screens
        if isOnCriticalPath {
            debugLog("🎯 Critical path event (100% captured): \(event.type)")
            uploader?.enqueue(event: event, metadata: sdkMetadata)
            delegate?.didDetectEvent(event)
            return
        }

        // HIGH RISK: Always 100% sampling when user is having problems
        if currentRiskScore >= highRiskThreshold {
            debugLog("🚨 High risk event (100% captured): \(event.type)")
            uploader?.enqueue(event: event, metadata: sdkMetadata)
            delegate?.didDetectEvent(event)
            return
        }

        // Apply adaptive sampling (critical events bypass sampling)
        if effectiveSampleRate < 1.0 && !isCriticalEvent(event.type) {
            if Double.random(in: 0...1) > effectiveSampleRate {
                debugLog("Event sampled out: \(event.type) (effective rate: \(String(format: "%.2f", effectiveSampleRate)))")
                // Track dropped events for dashboard analytics
                uploader?.incrementDroppedEventCount()
                return
            }
        }

        debugLog("Enqueue event: \(event.type)")
        uploader?.enqueue(event: event, metadata: sdkMetadata)
        delegate?.didDetectEvent(event)
    }

    /// Events that indicate a risk signal (frustration, errors)
    private func isRiskSignalEvent(_ eventType: String) -> Bool {
        return eventType == "rage_tap" ||
               eventType == "dead_click" ||
               eventType == "uiHang" ||
               eventType == "error" ||
               eventType == "http_error" ||
               eventType.contains("error")
    }
    
    /// Critical events that should never be sampled out
    private func isCriticalEvent(_ eventType: String) -> Bool {
        let criticalTypes: Set<String> = [
            "crash",
            "uiHang",
            "rage_tap",
            "dead_click",
            "session_start",
            "session_end",
            "memory_warning"
        ]
        return criticalTypes.contains(eventType)
    }
    
    // MARK: - Adaptive Sampling (Activity-Based)
    
    /// Events that indicate user interaction
    private func isUserInteractionEvent(_ eventType: String) -> Bool {
        let interactionTypes: Set<String> = [
            "button_tap",
            "screen_view",
            "scroll",
            "gesture",
            "custom" // Custom events often indicate user actions
        ]
        return interactionTypes.contains(eventType) || eventType.contains("tap") || eventType.contains("click")
    }
    
    /// Track a user interaction for activity level calculation
    private func trackInteraction() {
        let now = Date()
        recentInteractionTimestamps.append(now)
        
        // Clean up old timestamps outside the window
        let cutoff = now.addingTimeInterval(-interactionWindow)
        recentInteractionTimestamps.removeAll { $0 < cutoff }
    }
    
    /// Start the activity level monitor
    private func startActivityMonitor() {
        activityCheckTimer?.invalidate()
        activityCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.updateActivityLevel()
        }
    }
    
    /// Calculate and update activity level multiplier
    private func updateActivityLevel() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-interactionWindow)
        recentInteractionTimestamps.removeAll { $0 < cutoff }
        
        let interactionsPerMinute = recentInteractionTimestamps.count
        let previousMultiplier = currentActivityMultiplier
        
        if interactionsPerMinute > highActivityThreshold {
            // High activity: reduce sampling to save CPU
            currentActivityMultiplier = 0.3
        } else if interactionsPerMinute < lowActivityThreshold {
            // Low activity: full sampling (user is passive, events are rare anyway)
            currentActivityMultiplier = 1.0
        } else {
            // Medium activity: moderate sampling
            currentActivityMultiplier = 0.6
        }
        
        if previousMultiplier != currentActivityMultiplier {
            debugLog("Activity level changed: \(interactionsPerMinute) interactions/min → multiplier=\(currentActivityMultiplier)")
        }
    }
    
    /// Stop the activity monitor
    private func stopActivityMonitor() {
        activityCheckTimer?.invalidate()
        activityCheckTimer = nil
    }

    // MARK: - Risk Score Calculation

    /// Track a risk signal event
    private func trackRiskSignal(type: String) {
        let now = Date()

        switch type {
        case "rage_tap":
            recentRageTaps.append(now)
        case "dead_click":
            recentDeadClicks.append(now)
        case "error", "crash":
            recentErrors.append(now)
        case "uiHang":
            recentUIHangs.append(now)
        case "http_error":
            recentHTTPErrors.append(now)
        default:
            break
        }

        // Update risk score after tracking
        updateRiskScore()
    }

    // MARK: - Risk Score Constants
    
    /// Decay factor for diminishing returns (0.0 - 1.0)
    /// Each subsequent event contributes weight * decay^n
    private let riskDecayFactor: Double = 0.8
    
    /// Event weights for risk calculation
    private let rageTapWeight: Double = 15
    private let deadClickWeight: Double = 10
    private let errorWeight: Double = 20
    private let uiHangWeight: Double = 25
    private let httpErrorWeight: Double = 8
    private let previousCrashBonus: Double = 30
    
    /// Calculate diminishing score for event count
    /// Uses decay factor to prevent score explosion with many events
    /// Example with decay=0.8: 1st=15, 2nd=12, 3rd=9.6, 4th=7.7...
    private func diminishingScore(count: Int, weight: Double) -> Double {
        guard count > 0 else { return 0 }
        var total: Double = 0
        for i in 0..<count {
            total += weight * pow(riskDecayFactor, Double(i))
        }
        return total
    }

    /// Calculate and update user risk score (0-100)
    /// Uses diminishing returns algorithm - same as Web SDK
    private func updateRiskScore() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-riskWindow)

        // Clean up old signals
        recentRageTaps.removeAll { $0 < cutoff }
        recentDeadClicks.removeAll { $0 < cutoff }
        recentErrors.removeAll { $0 < cutoff }
        recentUIHangs.removeAll { $0 < cutoff }
        recentHTTPErrors.removeAll { $0 < cutoff }

        // Calculate score using diminishing returns
        // Prevents score explosion with many events
        var score: Double = 0

        // Rage taps: first=15, subsequent decay by 0.8
        score += diminishingScore(count: recentRageTaps.count, weight: rageTapWeight)

        // Dead clicks: first=10, subsequent decay
        score += diminishingScore(count: recentDeadClicks.count, weight: deadClickWeight)

        // Errors: first=20, subsequent decay
        score += diminishingScore(count: recentErrors.count, weight: errorWeight)

        // UI Hangs: first=25, subsequent decay
        score += diminishingScore(count: recentUIHangs.count, weight: uiHangWeight)

        // HTTP errors: first=8, subsequent decay
        score += diminishingScore(count: recentHTTPErrors.count, weight: httpErrorWeight)

        // Previous crash bonus (flat, no decay)
        if hadCrashInPreviousSession {
            score += previousCrashBonus
        }

        let previousScore = currentRiskScore
        currentRiskScore = min(Int(score), 100)

        if previousScore != currentRiskScore {
            debugLog("🚨 Risk score changed: \(previousScore) → \(currentRiskScore)")
        }
    }

    /// Check if previous session had a crash (called on configure)
    private func checkPreviousCrash() {
        // Check if crash marker file exists from SimpleCrashReporter
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        guard let cacheDir = paths.first else { return }
        let crashDir = cacheDir.appendingPathComponent("AppVitality/Crashes")

        if let files = try? FileManager.default.contentsOfDirectory(atPath: crashDir.path) {
            hadCrashInPreviousSession = files.contains { $0.contains("crash") }
            if hadCrashInPreviousSession {
                debugLog("⚠️ Previous session had a crash - elevated risk monitoring")
            }
        }
    }

    /// Get effective sample rate considering both activity and risk
    /// Risk ALWAYS wins over activity (problems > performance)
    private func getEffectiveSampleRate() -> Double {
        let baseSampleRate = options?.eventSampleRate ?? 1.0

        // HIGH RISK: Override everything, capture all events
        if currentRiskScore >= highRiskThreshold {
            debugLog("🚨 High risk detected (score: \(currentRiskScore)) - 100% sampling")
            return 1.0
        }

        // MEDIUM RISK: Boost sampling but respect some throttling
        if currentRiskScore >= mediumRiskThreshold {
            let boostedRate = min(baseSampleRate * 1.5, 1.0)
            debugLog("⚠️ Medium risk (score: \(currentRiskScore)) - boosted to \(String(format: "%.0f", boostedRate * 100))%")
            return boostedRate
        }

        // LOW RISK: Apply normal activity-based sampling
        return baseSampleRate * currentActivityMultiplier
    }

    func handleCrash(report: AppVitalityCrashReport) {
        print("☠️ [AppVitalityKit] Crash detected: \(report.title)")
        debugLog("Enqueue crash: \(report.title)")
        delegate?.didDetectCrash(report.logString)
        uploader?.enqueueCrashReport(title: report.title,
                                     stackTrace: report.stackTrace,
                                     observedAt: report.observedAt,
                                     breadcrumbs: report.breadcrumbs,
                                     environment: report.environment)
    }
    
    /// Synchronous crash handling for signal handlers
    /// Must be called from signal handler context (no async queues)
    func handleCrashSync(report: AppVitalityCrashReport) {
        print("☠️ [AppVitalityKit] Crash detected (sync): \(report.title)")
        print("☠️ [AppVitalityKit] Stack trace:\n\(report.stackTrace)")
        debugLog("Enqueue crash (sync): \(report.title)")
        delegate?.didDetectCrash(report.logString)
        uploader?.enqueueCrashReportSync(title: report.title,
                                        stackTrace: report.stackTrace,
                                        observedAt: report.observedAt,
                                        breadcrumbs: report.breadcrumbs,
                                        environment: report.environment)
    }

    func handleLegacyCrashLog(_ log: String) {
        delegate?.didDetectCrash(log)
        uploader?.enqueueCrash(log)
    }

    func debugLog(_ message: String) {
        guard options?.enableDebugLogging == true else { return }
        print("🔍 AppVitalityKit DEBUG: \(message)")
    }
}

// MARK: - Global Helper for fatalError

/// Helper function to report crash before calling fatalError
/// Usage: fatalErrorWithReport("Test crash")
public func fatalErrorWithReport(_ message: String, file: StaticString = #file, line: UInt = #line) -> Never {
    AppVitalityKit.shared.reportCrash(message: message, file: String(describing: file), line: Int(line))
    fatalError(message, file: file, line: line)
}

// MARK: - Legacy Configuration (Deprecated)

extension AppVitalityKit {
    
    @available(*, deprecated, message: "Use configure(apiKey:options:) instead")
    public struct Configuration {
        public typealias AutomaticFeature = Feature
        public typealias PowerPolicy = Options.PowerPolicy
        
        public struct CloudSync {
            public let endpoint: URL
            public let apiKey: String
            public let flushInterval: TimeInterval
            public let maxBatchSize: Int
            
            public init(apiKey: String,
                        endpoint: URL = AppVitalityKit.defaultEndpoint,
                        flushInterval: TimeInterval = 10,
                        maxBatchSize: Int = 20) {
                self.endpoint = endpoint
                self.apiKey = apiKey
                self.flushInterval = flushInterval
                self.maxBatchSize = maxBatchSize
            }
        }
        
        public var features: Set<Feature>
        public var policy: Options.PowerPolicy
        public var cloud: CloudSync?
        
        public init(features: Set<Feature> = Feature.recommended,
                    policy: Options.PowerPolicy = .moderate,
                    cloud: CloudSync? = nil) {
            self.features = features
            self.policy = policy
            self.cloud = cloud
        }
    }
    
    @available(*, deprecated, message: "Use configure(apiKey:options:) instead")
    public func configure(with config: Configuration) {
        guard let cloud = config.cloud else {
            print("⚠️ AppVitalityKit: No API key provided. Use configure(apiKey:) instead.")
            return
        }
        
        let options = Options(
            features: config.features,
            policy: config.policy,
            flushInterval: cloud.flushInterval,
            maxBatchSize: cloud.maxBatchSize,
            customEndpoint: cloud.endpoint == Self.defaultEndpoint ? nil : cloud.endpoint
        )
        
        configure(apiKey: cloud.apiKey, options: options)
    }
    
    @available(*, deprecated, renamed: "currentOptions")
    public var currentConfig: Configuration? {
        guard let opts = options, let key = apiKey else { return nil }
        return Configuration(
            features: opts.features,
            policy: opts.policy,
            cloud: .init(apiKey: key, flushInterval: opts.flushInterval, maxBatchSize: opts.maxBatchSize)
        )
    }
}
