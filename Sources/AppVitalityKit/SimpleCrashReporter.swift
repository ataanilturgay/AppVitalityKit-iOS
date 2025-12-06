import Foundation
import UIKit
import Darwin

// MARK: - C-level signal handler (async-signal-safe)
// This is called directly from the OS, must be minimal and safe

private var previousHandlers: [Int32: (@convention(c) (Int32) -> Void)?] = [:]

// Pre-computed crash directory path (set during start())
private var crashMarkerPath: UnsafeMutablePointer<CChar>?

private let cSignalHandler: @convention(c) (Int32) -> Void = { signal in
    // Write crash marker to disk using POSIX (async-signal-safe)
    // CRITICAL: Do NOT use any Swift/Obj-C objects here - only C functions
    
    guard let path = crashMarkerPath else { return }
    
    // Create simple marker content (just signal number as ASCII)
    var buffer: [CChar] = Array(repeating: 0, count: 32)
    
    // Write "SIGNAL:" prefix
    let prefix: [CChar] = [0x53, 0x49, 0x47, 0x4E, 0x41, 0x4C, 0x3A] // "SIGNAL:"
    for (i, c) in prefix.enumerated() {
        buffer[i] = c
    }
    
    // Convert signal number to ASCII digits
    var sig = signal
    var digits: [CChar] = []
    if sig == 0 {
        digits = [0x30] // "0"
    } else {
        while sig > 0 {
            digits.insert(CChar(0x30 + (sig % 10)), at: 0)
            sig /= 10
        }
    }
    
    for (i, d) in digits.enumerated() {
        buffer[7 + i] = d
    }
    buffer[7 + digits.count] = 0x0A // newline
    
    // Open file with POSIX
    let fd = Darwin.open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    if fd >= 0 {
        _ = Darwin.write(fd, buffer, strlen(buffer))
        Darwin.fsync(fd)
        Darwin.close(fd)
    }
    
    // Call previous handler if exists
    if let previous = previousHandlers[signal] {
        previous?(signal)
    }
    
    // Re-raise signal with default handler to let OS handle it
    Darwin.signal(signal, SIG_DFL)
    Darwin.raise(signal)
}

private let uncaughtExceptionHandler: @convention(c) (NSException) -> Void = { exception in
    SimpleCrashReporter.handleException(exception)
}

public class SimpleCrashReporter {
    
    private static let crashMarkerFile = "appvitality_crash_marker.txt"
    private static let crashDataFile = "appvitality_crash_data.json"
    
    // MARK: - Public API
    
    public static func start() {
        print("☠️ [SimpleCrashReporter] Starting crash reporter...")
        
        // 0. Pre-compute crash marker path for signal handler (MUST be done before installing handlers)
        setupCrashMarkerPath()
        
        // 1. Check for previous crash FIRST (before installing new handlers)
        checkPreviousCrash()
        
        // 2. Uncaught Exception Handler (NSException)
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)
        
        // 3. Signal Handlers using sigaction (more reliable than signal())
        installSignalHandler(SIGABRT)
        installSignalHandler(SIGILL)
        installSignalHandler(SIGSEGV)
        installSignalHandler(SIGFPE)
        installSignalHandler(SIGBUS)
        installSignalHandler(SIGPIPE)
        installSignalHandler(SIGTRAP)
        
        // 4. Periodically save breadcrumbs to disk (so we have them after crash)
        saveBreadcrumbsToDiskPeriodically()
        
        print("☠️ [SimpleCrashReporter] Crash reporter ready")
    }
    
    // MARK: - Setup Crash Marker Path
    
    private static func setupCrashMarkerPath() {
        guard let dir = crashDirectory else {
            print("☠️ [SimpleCrashReporter] ERROR: Could not create crash directory")
            return
        }
        
        let markerPath = dir.appendingPathComponent(crashMarkerFile).path
        
        // Allocate persistent C string for signal handler
        let cString = strdup(markerPath)
        crashMarkerPath = cString
        
        print("☠️ [SimpleCrashReporter] Crash marker path: \(markerPath)")
    }
    
    // MARK: - Signal Installation (sigaction)
    
    private static func installSignalHandler(_ sig: Int32) {
        var oldAction = sigaction()
        var newAction = sigaction()
        
        newAction.__sigaction_u.__sa_handler = cSignalHandler
        newAction.sa_flags = SA_NODEFER
        sigemptyset(&newAction.sa_mask)
        
        if sigaction(sig, &newAction, &oldAction) == 0 {
            // Store previous handler for chaining
            previousHandlers[sig] = oldAction.__sigaction_u.__sa_handler
            print("☠️ [SimpleCrashReporter] Installed handler for signal \(sig)")
        } else {
            print("☠️ [SimpleCrashReporter] Failed to install handler for signal \(sig)")
        }
    }
    
    // MARK: - Async-Signal-Safe Crash Marker (POSIX write) - Called from Swift code only
    
    static func writeCrashMarkerSync(signal: Int32) {
        guard let dir = crashDirectory else { return }
        let markerPath = dir.appendingPathComponent(crashMarkerFile).path
        
        let timestamp = Date().timeIntervalSince1970
        let content = "SIGNAL:\(signal)\nTIME:\(timestamp)\n"
        
        markerPath.withCString { pathPtr in
            let fd = Darwin.open(pathPtr, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            if fd >= 0 {
                content.withCString { dataPtr in
                    _ = Darwin.write(fd, dataPtr, strlen(dataPtr))
                }
                Darwin.fsync(fd)
                Darwin.close(fd)
            }
        }
    }
    
    // MARK: - Crash Directory
    
    private static var _crashDirectory: URL?
    
    private static var crashDirectory: URL? {
        if let dir = _crashDirectory {
            return dir
        }
        
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = cacheDir.appendingPathComponent("AppVitality/Crashes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _crashDirectory = dir
        return dir
    }
    
    // MARK: - Exception Handler (NSException - Obj-C)
    
    fileprivate static func handleException(_ exception: NSException) {
        print("☠️ [SimpleCrashReporter] Exception caught: \(exception.name)")
        
        let context = generateContextSnapshot()
        let breadcrumbs = BreadcrumbLogger.shared.getLogs()
        let stackTrace = exception.callStackSymbols.joined(separator: "\n")

        let crashLog = """
        [CRASH REPORT - EXCEPTION]
        Date: \(Date())
        Name: \(exception.name)
        Reason: \(exception.reason ?? "Unknown")

        [ENVIRONMENT]
        \(context.description)

        [BREADCRUMBS (Last Actions)]
        \(breadcrumbs.isEmpty ? "No breadcrumbs recorded." : breadcrumbs)

        [STACK TRACE]
        \(stackTrace)
        """

        let report = AppVitalityCrashReport(
            title: exception.name.rawValue,
            stackTrace: stackTrace,
            logString: crashLog,
            observedAt: Date(),
            breadcrumbs: BreadcrumbLogger.shared.getLogEntries().map { ["message": AnyEncodable($0)] },
            environment: context.data
        )

        // Save crash data to disk immediately
        saveCrashDataSync(report: report)
        
        // Try to send (best effort)
        AppVitalityKit.shared.handleCrashSync(report: report)
    }
    
    // MARK: - Save Crash Data to Disk (Synchronous)
    
    private static func saveCrashDataSync(report: AppVitalityCrashReport) {
        guard let dir = crashDirectory else { return }
        let dataPath = dir.appendingPathComponent(crashDataFile)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            try data.write(to: dataPath, options: .atomic)
            print("☠️ [SimpleCrashReporter] Crash data saved to disk")
        } catch {
            print("☠️ [SimpleCrashReporter] Failed to save crash data: \(error)")
        }
    }
    
    // MARK: - Previous Crash Check (On App Launch)
    
    private static func checkPreviousCrash() {
        guard let dir = crashDirectory else { return }
        
        let markerPath = dir.appendingPathComponent(crashMarkerFile)
        let dataPath = dir.appendingPathComponent(crashDataFile)
        
        print("☠️ [SimpleCrashReporter] Checking for crash marker at: \(markerPath.path)")
        
        // Check for crash marker
        if FileManager.default.fileExists(atPath: markerPath.path) {
            print("☠️ [SimpleCrashReporter] ⚠️ CRASH MARKER FOUND - previous session crashed!")
            
            // Read marker content
            if let markerContent = try? String(contentsOf: markerPath, encoding: .utf8) {
                print("☠️ [SimpleCrashReporter] Marker content: \(markerContent)")
                
                // Parse signal from marker
                var signalName = "Unknown Signal"
                if let signalLine = markerContent.components(separatedBy: "\n").first,
                   signalLine.hasPrefix("SIGNAL:"),
                   let signalNum = Int32(signalLine.replacingOccurrences(of: "SIGNAL:", with: "")) {
                    signalName = signalNameFor(signalNum)
                }
                
                // Check if we have detailed crash data
                if FileManager.default.fileExists(atPath: dataPath.path),
                   let data = try? Data(contentsOf: dataPath) {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    if let report = try? decoder.decode(AppVitalityCrashReport.self, from: data) {
                        // We have detailed data, send it
                        print("☠️ [SimpleCrashReporter] Sending detailed crash report: \(report.title)")
                        AppVitalityKit.shared.handleCrashSync(report: report)
                    } else {
                        print("☠️ [SimpleCrashReporter] Could not decode crash data, sending minimal report")
                        sendMinimalReport(signalName: signalName)
                    }
                } else {
                    // Only have marker, create minimal report from saved breadcrumbs
                    print("☠️ [SimpleCrashReporter] No detailed crash data, sending minimal report")
                    sendMinimalReport(signalName: signalName)
                }
            }
            
            // Clean up marker and data files
            try? FileManager.default.removeItem(at: markerPath)
            try? FileManager.default.removeItem(at: dataPath)
            print("☠️ [SimpleCrashReporter] Cleaned up crash files")
        } else {
            print("☠️ [SimpleCrashReporter] No crash marker found - clean start")
        }
    }
    
    private static func sendMinimalReport(signalName: String) {
        let breadcrumbs = loadBreadcrumbsFromDisk()
        let report = AppVitalityCrashReport(
            title: signalName,
            stackTrace: "Stack trace not available (captured from signal)",
            logString: "[CRASH REPORT - SIGNAL]\nSignal: \(signalName)\nNote: Detailed stack trace unavailable",
            observedAt: Date(),
            breadcrumbs: breadcrumbs.map { ["message": AnyEncodable($0)] },
            environment: nil
        )
        print("☠️ [SimpleCrashReporter] Sending minimal crash report: \(signalName)")
        AppVitalityKit.shared.handleCrashSync(report: report)
    }
    
    // MARK: - Breadcrumbs Persistence
    
    private static let breadcrumbsFile = "appvitality_breadcrumbs.txt"
    
    private static func saveBreadcrumbsToDiskPeriodically() {
        // Save breadcrumbs every 5 seconds
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            saveBreadcrumbsToDisk()
        }
        // Also save immediately
        saveBreadcrumbsToDisk()
    }
    
    private static func saveBreadcrumbsToDisk() {
        guard let dir = crashDirectory else { return }
        let path = dir.appendingPathComponent(breadcrumbsFile)
        let content = BreadcrumbLogger.shared.getLogs()
        try? content.write(to: path, atomically: true, encoding: .utf8)
    }
    
    private static func loadBreadcrumbsFromDisk() -> [String] {
        guard let dir = crashDirectory else { return [] }
        let path = dir.appendingPathComponent(breadcrumbsFile)
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
    
    // MARK: - Helpers
    
    private static func signalNameFor(_ signal: Int32) -> String {
        switch signal {
        case SIGABRT: return "SIGABRT (Abort)"
        case SIGILL:  return "SIGILL (Illegal Instruction)"
        case SIGSEGV: return "SIGSEGV (Segmentation Fault)"
        case SIGFPE:  return "SIGFPE (Floating Point Exception)"
        case SIGBUS:  return "SIGBUS (Bus Error)"
        case SIGPIPE: return "SIGPIPE (Broken Pipe)"
        case SIGTRAP: return "SIGTRAP (Trace/Breakpoint Trap)"
        default: return "Signal \(signal)"
        }
    }

    private struct CrashContext {
        let description: String
        let data: [String: AnyEncodable]
    }

    private static func generateContextSnapshot() -> CrashContext {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        let batteryLevel = String(format: "%.0f%%", device.batteryLevel * 100)
        let batteryState = device.batteryState == .charging ? "Charging" : "Unplugged"
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled ? "Enabled" : "Disabled"

        var thermalState = "Unknown"
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalState = "Nominal"
        case .fair: thermalState = "Fair"
        case .serious: thermalState = "Serious (Throttling)"
        case .critical: thermalState = "Critical (Hot)"
        @unknown default: break
        }

        var memoryUsage = "Unknown"
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            memoryUsage = String(format: "%.1f MB", usedMB)
        }

        let orientation = device.orientation.isLandscape ? "Landscape" : "Portrait"

        let description = """
        Device: \(device.systemName) \(device.systemVersion)
        Model: \(device.model)
        Battery: \(batteryLevel) (\(batteryState))
        Low Power Mode: \(lowPowerMode)
        Thermal State: \(thermalState)
        Memory Usage: \(memoryUsage)
        Orientation: \(orientation)
        """

        let data: [String: AnyEncodable] = [
            "system": AnyEncodable(device.systemName),
            "systemVersion": AnyEncodable(device.systemVersion),
            "model": AnyEncodable(device.model),
            "batteryLevel": AnyEncodable(batteryLevel),
            "batteryState": AnyEncodable(batteryState),
            "lowPowerMode": AnyEncodable(lowPowerMode),
            "thermalState": AnyEncodable(thermalState),
            "memoryUsage": AnyEncodable(memoryUsage),
            "orientation": AnyEncodable(orientation)
        ]

        return CrashContext(description: description, data: data)
    }
}
