import XCTest
@testable import AppVitalityKit

final class AppVitalityKitTests: XCTestCase {
    
    // MARK: - Configuration Tests
    
    func testDefaultConfiguration() {
        let config = AppVitalityKit.Configuration()
        
        XCTAssertEqual(config.policy, .strict)
        XCTAssertTrue(config.features.contains(.metricKitReporting))
        XCTAssertTrue(config.features.contains(.networkMonitoring))
        XCTAssertTrue(config.features.contains(.fpsMonitor))
        XCTAssertTrue(config.features.contains(.cpuMonitor))
        XCTAssertTrue(config.features.contains(.autoActionTracking))
        XCTAssertNil(config.cloud)
    }
    
    func testCustomConfiguration() {
        let config = AppVitalityKit.Configuration(
            features: [.crashReporting, .memoryMonitor],
            policy: .relaxed,
            cloud: nil
        )
        
        XCTAssertEqual(config.policy, .relaxed)
        XCTAssertEqual(config.features.count, 2)
        XCTAssertTrue(config.features.contains(.crashReporting))
        XCTAssertTrue(config.features.contains(.memoryMonitor))
        XCTAssertFalse(config.features.contains(.fpsMonitor))
    }
    
    func testCloudSyncConfiguration() {
        let endpoint = URL(string: "https://api.example.com/events")!
        let cloudSync = AppVitalityKit.Configuration.CloudSync(
            endpoint: endpoint,
            apiKey: "test-api-key",
            flushInterval: 15,
            maxBatchSize: 50
        )
        
        XCTAssertEqual(cloudSync.endpoint, endpoint)
        XCTAssertEqual(cloudSync.apiKey, "test-api-key")
        XCTAssertEqual(cloudSync.flushInterval, 15)
        XCTAssertEqual(cloudSync.maxBatchSize, 50)
    }
    
    func testCloudSyncDefaultValues() {
        let endpoint = URL(string: "https://api.example.com/events")!
        let cloudSync = AppVitalityKit.Configuration.CloudSync(
            endpoint: endpoint,
            apiKey: "test-key"
        )
        
        XCTAssertEqual(cloudSync.flushInterval, 10) // Default
        XCTAssertEqual(cloudSync.maxBatchSize, 20) // Default
    }
    
    func testAllPowerPolicies() {
        let strictConfig = AppVitalityKit.Configuration(policy: .strict)
        let moderateConfig = AppVitalityKit.Configuration(policy: .moderate)
        let relaxedConfig = AppVitalityKit.Configuration(policy: .relaxed)
        
        XCTAssertEqual(strictConfig.policy, .strict)
        XCTAssertEqual(moderateConfig.policy, .moderate)
        XCTAssertEqual(relaxedConfig.policy, .relaxed)
    }
    
    func testAllAutomaticFeatures() {
        let allFeatures: Set<AppVitalityKit.Configuration.AutomaticFeature> = [
            .metricKitReporting,
            .networkMonitoring,
            .mainThreadWatchdog,
            .memoryMonitor,
            .crashReporting,
            .fpsMonitor,
            .cpuMonitor,
            .autoActionTracking
        ]
        
        let config = AppVitalityKit.Configuration(features: allFeatures)
        XCTAssertEqual(config.features.count, 8)
    }
}

// MARK: - BreadcrumbLogger Tests

final class BreadcrumbLoggerTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clear logs before each test by logging and waiting
    }
    
    func testLogSingleMessage() {
        let logger = BreadcrumbLogger.shared
        logger.log("Test message")
        
        // Wait for async queue
        let expectation = self.expectation(description: "Log written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let logs = logger.getLogs()
            XCTAssertTrue(logs.contains("Test message"))
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testLogMultipleMessages() {
        let logger = BreadcrumbLogger.shared
        
        logger.log("First action")
        logger.log("Second action")
        logger.log("Third action")
        
        let expectation = self.expectation(description: "Logs written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let entries = logger.getLogEntries()
            
            // Check that all messages are present (they include timestamp prefix)
            let hasFirst = entries.contains { $0.contains("First action") }
            let hasSecond = entries.contains { $0.contains("Second action") }
            let hasThird = entries.contains { $0.contains("Third action") }
            
            XCTAssertTrue(hasFirst)
            XCTAssertTrue(hasSecond)
            XCTAssertTrue(hasThird)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testLogEntriesContainTimestamp() {
        let logger = BreadcrumbLogger.shared
        logger.log("Timestamped message")
        
        let expectation = self.expectation(description: "Log with timestamp")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let logs = logger.getLogs()
            // Logs should have format: [HH:MM:SS] Message
            XCTAssertTrue(logs.contains("["))
            XCTAssertTrue(logs.contains("]"))
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testGetLogsReturnsJoinedString() {
        let logger = BreadcrumbLogger.shared
        
        logger.log("Line 1")
        logger.log("Line 2")
        
        let expectation = self.expectation(description: "Joined logs")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let logs = logger.getLogs()
            // Should contain newlines between entries
            XCTAssertTrue(logs.contains("\n") || logger.getLogEntries().count == 1)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testGetLogEntriesReturnsArray() {
        let logger = BreadcrumbLogger.shared
        
        let entries = logger.getLogEntries()
        XCTAssertTrue(entries is [String])
    }
    
    func testThreadSafety() {
        let logger = BreadcrumbLogger.shared
        let expectation = self.expectation(description: "Thread safe logging")
        
        let group = DispatchGroup()
        
        // Log from multiple threads simultaneously
        for i in 0..<10 {
            group.enter()
            DispatchQueue.global(qos: .background).async {
                logger.log("Background log \(i)")
                group.leave()
            }
        }
        
        for i in 0..<10 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                logger.log("UserInitiated log \(i)")
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            // Should not crash and logs should be accessible
            let _ = logger.getLogs()
            let _ = logger.getLogEntries()
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2.0)
    }
}

// MARK: - AnyEncodable Tests

final class AnyEncodableTests: XCTestCase {
    
    func testEncodeString() throws {
        let value = AnyEncodable("test string")
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let decoded = String(data: data, encoding: .utf8)
        
        XCTAssertEqual(decoded, "\"test string\"")
    }
    
    func testEncodeInt() throws {
        let value = AnyEncodable(42)
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let decoded = String(data: data, encoding: .utf8)
        
        XCTAssertEqual(decoded, "42")
    }
    
    func testEncodeDouble() throws {
        let value = AnyEncodable(3.14)
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let decoded = String(data: data, encoding: .utf8)
        
        XCTAssertNotNil(decoded)
        XCTAssertTrue(decoded!.contains("3.14"))
    }
    
    func testEncodeBool() throws {
        let trueValue = AnyEncodable(true)
        let falseValue = AnyEncodable(false)
        let encoder = JSONEncoder()
        
        let trueData = try encoder.encode(trueValue)
        let falseData = try encoder.encode(falseValue)
        
        XCTAssertEqual(String(data: trueData, encoding: .utf8), "true")
        XCTAssertEqual(String(data: falseData, encoding: .utf8), "false")
    }
    
    func testEncodeArray() throws {
        let value = AnyEncodable([1, 2, 3])
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let decoded = String(data: data, encoding: .utf8)
        
        XCTAssertEqual(decoded, "[1,2,3]")
    }
    
    func testEncodeDictionary() throws {
        let value = AnyEncodable(["key": "value"])
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let decoded = String(data: data, encoding: .utf8)
        
        XCTAssertNotNil(decoded)
        XCTAssertTrue(decoded!.contains("key"))
        XCTAssertTrue(decoded!.contains("value"))
    }
    
    func testEncodeNil() throws {
        let value = AnyEncodable(nil as String?)
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let decoded = String(data: data, encoding: .utf8)
        
        XCTAssertEqual(decoded, "null")
    }
}

// MARK: - Monitor Start/Stop Tests (Smoke Tests)

final class MonitorSmokeTests: XCTestCase {
    
    func testCPUMonitorStartStop() {
        let monitor = CPUMonitor.shared
        
        // Should not crash
        monitor.start()
        monitor.stop()
        
        // Multiple starts should be safe
        monitor.start()
        monitor.start()
        monitor.stop()
    }
    
    func testMemoryMonitorStartStop() {
        let monitor = MemoryMonitor.shared
        
        // Should not crash
        monitor.start()
        monitor.stop()
        
        // Multiple starts should be safe
        monitor.start()
        monitor.start()
        monitor.stop()
    }
    
    func testFPSMonitorStartStop() {
        let monitor = FPSMonitor.shared
        
        // Should not crash
        monitor.start()
        monitor.stop()
        
        // Multiple starts should be safe
        monitor.start()
        monitor.start()
        monitor.stop()
    }
    
    func testMainThreadWatchdogStartStop() {
        let watchdog = MainThreadWatchdog.shared
        
        // Should not crash
        watchdog.start()
        watchdog.stop()
        
        // Multiple starts should be safe
        watchdog.start()
        watchdog.start()
        watchdog.stop()
    }
}

// MARK: - Network Monitor Configuration Tests

final class NetworkMonitorConfigurationTests: XCTestCase {
    
    func testDefaultConfiguration() {
        let config = AppVitalityNetworkMonitor.configuration
        
        // Configuration should be accessible
        XCTAssertNotNil(config)
    }
    
    func testConfigurationIsModifiable() {
        // Save original values
        let originalBlockLowPower = AppVitalityNetworkMonitor.configuration.blockRequestsInLowPowerMode
        let originalBlockBackground = AppVitalityNetworkMonitor.configuration.blockRequestsInBackground
        let originalVerbose = AppVitalityNetworkMonitor.configuration.verboseLogging
        
        // Modify
        AppVitalityNetworkMonitor.configuration.blockRequestsInLowPowerMode = true
        AppVitalityNetworkMonitor.configuration.blockRequestsInBackground = true
        AppVitalityNetworkMonitor.configuration.verboseLogging = false
        
        // Verify changes
        XCTAssertTrue(AppVitalityNetworkMonitor.configuration.blockRequestsInLowPowerMode)
        XCTAssertTrue(AppVitalityNetworkMonitor.configuration.blockRequestsInBackground)
        XCTAssertFalse(AppVitalityNetworkMonitor.configuration.verboseLogging)
        
        // Restore
        AppVitalityNetworkMonitor.configuration.blockRequestsInLowPowerMode = originalBlockLowPower
        AppVitalityNetworkMonitor.configuration.blockRequestsInBackground = originalBlockBackground
        AppVitalityNetworkMonitor.configuration.verboseLogging = originalVerbose
    }
}

// MARK: - Crash Report Model Tests

final class CrashReportTests: XCTestCase {
    
    func testCrashReportInitialization() {
        let breadcrumbs: [[String: AnyEncodable]] = [
            ["action": AnyEncodable("Action 1")],
            ["action": AnyEncodable("Action 2")]
        ]
        let environment: [String: AnyEncodable] = [
            "os_version": AnyEncodable("17.0"),
            "device": AnyEncodable("iPhone")
        ]
        
        let report = AppVitalityCrashReport(
            title: "Test Crash",
            stackTrace: "Line 1\nLine 2\nLine 3",
            logString: "Full crash log here",
            observedAt: Date(),
            breadcrumbs: breadcrumbs,
            environment: environment
        )
        
        XCTAssertEqual(report.title, "Test Crash")
        XCTAssertEqual(report.stackTrace, "Line 1\nLine 2\nLine 3")
        XCTAssertEqual(report.breadcrumbs?.count, 2)
        XCTAssertNotNil(report.environment)
        XCTAssertNotNil(report.observedAt)
    }
    
    func testCrashReportLogStringIsStored() {
        let report = AppVitalityCrashReport(
            title: "EXC_BAD_ACCESS",
            stackTrace: "0x00001 main\n0x00002 start",
            logString: "Complete log with EXC_BAD_ACCESS and main",
            observedAt: Date(),
            breadcrumbs: nil,
            environment: nil
        )
        
        XCTAssertTrue(report.logString.contains("EXC_BAD_ACCESS"))
        XCTAssertTrue(report.logString.contains("main"))
    }
    
    func testCrashReportWithNilBreadcrumbs() {
        let report = AppVitalityCrashReport(
            title: "Crash",
            stackTrace: "Stack",
            logString: "Log",
            observedAt: Date(),
            breadcrumbs: nil,
            environment: nil
        )
        
        XCTAssertNil(report.breadcrumbs)
        XCTAssertFalse(report.logString.isEmpty)
    }
    
    func testCrashReportWithEmptyBreadcrumbs() {
        let report = AppVitalityCrashReport(
            title: "Crash",
            stackTrace: "Stack",
            logString: "Log",
            observedAt: Date(),
            breadcrumbs: [],
            environment: [:]
        )
        
        XCTAssertEqual(report.breadcrumbs?.count, 0)
        XCTAssertEqual(report.environment?.count, 0)
    }
}

// MARK: - Singleton Pattern Tests

final class SingletonTests: XCTestCase {
    
    func testAppVitalityKitSingleton() {
        let instance1 = AppVitalityKit.shared
        let instance2 = AppVitalityKit.shared
        
        XCTAssertTrue(instance1 === instance2)
    }
    
    func testBreadcrumbLoggerSingleton() {
        let instance1 = BreadcrumbLogger.shared
        let instance2 = BreadcrumbLogger.shared
        
        XCTAssertTrue(instance1 === instance2)
    }
    
    func testCPUMonitorSingleton() {
        let instance1 = CPUMonitor.shared
        let instance2 = CPUMonitor.shared
        
        XCTAssertTrue(instance1 === instance2)
    }
    
    func testMemoryMonitorSingleton() {
        let instance1 = MemoryMonitor.shared
        let instance2 = MemoryMonitor.shared
        
        XCTAssertTrue(instance1 === instance2)
    }
    
    func testFPSMonitorSingleton() {
        let instance1 = FPSMonitor.shared
        let instance2 = FPSMonitor.shared
        
        XCTAssertTrue(instance1 === instance2)
    }
}
