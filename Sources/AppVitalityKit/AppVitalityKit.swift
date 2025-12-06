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
        case metricKitReporting // Collect energy and performance reports
        case networkMonitoring  // Monitor URLSession traffic and warn (does NOT block)
        case mainThreadWatchdog // Catch UI hangs
        case memoryMonitor      // Warn about excessive RAM usage
        case crashReporting     // Record basic crash reasons
        case fpsMonitor         // Monitor UI smoothness (Frame Drop)
        case cpuMonitor         // Monitor CPU usage and thermal state
        case autoActionTracking // Automatic UI Tracking (Taps, Screen Transitions)
        
        /// All available features
        public static let all: Set<Feature> = [
            .metricKitReporting,
            .networkMonitoring,
            .mainThreadWatchdog,
            .memoryMonitor,
            .crashReporting,
            .fpsMonitor,
            .cpuMonitor,
            .autoActionTracking
        ]
        
        /// Recommended features for most apps
        public static let recommended: Set<Feature> = [
            .fpsMonitor,
            .cpuMonitor,
            .crashReporting,
            .autoActionTracking
        ]
    }

    // MARK: - Options
    
    /// Configuration options for SDK behavior
    public struct Options {
        
        public enum PowerPolicy {
            case strict   // Most aggressive monitoring
            case moderate // Balanced
            case relaxed  // Minimal impact
        }
        
        /// Which features to enable
        public var features: Set<Feature>
        
        /// Power/performance policy
        public var policy: PowerPolicy
        
        /// How often to send batched events (seconds)
        public var flushInterval: TimeInterval
        
        /// Maximum events per batch
        public var maxBatchSize: Int
        
        /// Custom endpoint (nil = use default AppVitality API)
        public var customEndpoint: URL?

        /// Enable verbose debug logging (events, crashes enqueue)
        public var enableDebugLogging: Bool
        
        /// Default options with recommended features
        public init(
            features: Set<Feature> = Feature.recommended,
            policy: PowerPolicy = .moderate,
            flushInterval: TimeInterval = 10,
            maxBatchSize: Int = 20,
            customEndpoint: URL? = nil,
            enableDebugLogging: Bool = false
        ) {
            self.features = features
            self.policy = policy
            self.flushInterval = flushInterval
            self.maxBatchSize = maxBatchSize
            self.customEndpoint = customEndpoint
            self.enableDebugLogging = enableDebugLogging
        }
        
        /// Convenience: All features enabled
        public static var allFeatures: Options {
            Options(features: Feature.all)
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
    
    /// Initialize AppVitalityKit with your API key
    /// - Parameters:
    ///   - apiKey: Your project API key from AppVitality Dashboard
    ///   - options: Optional configuration (defaults to recommended settings)
    public func configure(apiKey: String, options: Options = Options()) {
        guard !isConfigured else {
            print("⚠️ AppVitalityKit is already configured.")
            return
        }

        self.apiKey = apiKey
        self.options = options
        self.isConfigured = true
        
        debugLog("Configuring with endpoint: \(options.customEndpoint?.absoluteString ?? Self.defaultEndpoint.absoluteString)")
        let featureList = options.features.map { "\($0)" }.joined(separator: ",")
        debugLog("Features: \(featureList)")

        // Setup cloud uploader (this loads and sends pending crashes with their breadcrumbs)
        let endpoint = options.customEndpoint ?? Self.defaultEndpoint
        let uploaderConfig = AppVitalityUploader.CloudConfig(
            endpoint: endpoint,
            apiKey: apiKey,
            flushInterval: options.flushInterval,
            maxBatchSize: options.maxBatchSize
        )
        self.uploader = AppVitalityUploader(config: uploaderConfig)
        
        // Clear breadcrumbs AFTER uploader processes pending crashes
        // This ensures crash reports include breadcrumbs from the crashed session
        BreadcrumbLogger.shared.clear()
        print("🧹 [AppVitalityKit] Previous session breadcrumbs cleared")

        print("🔋 AppVitalityKit is starting...")
        print("   ✅ Cloud Sync: Active (Batch upload)")

        // 1. MetricKit
        if options.features.contains(.metricKitReporting) {
            if #available(iOS 13.0, *) {
                _ = MetricKitCollector.shared
                print("   ✅ MetricKit Collector: Active")
            }
        }

        // 2. Network Monitoring
        if options.features.contains(.networkMonitoring) {
            URLProtocol.registerClass(AppVitalityNetworkMonitor.self)
            AppVitalityNetworkMonitor.configuration.blockRequestsInLowPowerMode = (options.policy == .strict)
            AppVitalityNetworkMonitor.configuration.blockRequestsInBackground = false
            AppVitalityNetworkMonitor.configuration.verboseLogging = true
            print("   ✅ Network Monitoring: Active")
        }

        // 3. Watchdog (UI Hangs)
        if options.features.contains(.mainThreadWatchdog) {
            MainThreadWatchdog.shared.start()
            print("   ✅ UI Watchdog: Active")
        }

        // 4. Memory Monitor
        if options.features.contains(.memoryMonitor) {
            MemoryMonitor.shared.start()
            print("   ✅ Memory Monitor: Active")
        }

        // 5. Crash Reporter
        if options.features.contains(.crashReporting) {
            SimpleCrashReporter.start()
            print("   ✅ Crash Reporter: Active")
        }

        // 6. FPS Monitor
        if options.features.contains(.fpsMonitor) {
            FPSMonitor.shared.start()
            print("   ✅ FPS Monitor: Active")
        }

        // 7. CPU Monitor
        if options.features.contains(.cpuMonitor) {
            CPUMonitor.shared.start()
            print("   ✅ CPU Monitor: Active")
        }

        // 8. Auto Action Tracking
        if options.features.contains(.autoActionTracking) {
            UIViewController.enableLifecycleTracking()
            UIControl.enableActionTracking()
            print("   ✅ Auto Tracker: Active")
        }

        print("🚀 AppVitalityKit is ready. (\(options.features.count) features enabled)")
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
            title: "FatalError: \(message)",
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
        debugLog("Enqueue event: \(event.type)")
        uploader?.enqueue(event: event)
        delegate?.didDetectEvent(event)
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

    private func debugLog(_ message: String) {
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
