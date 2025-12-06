import Foundation
import UIKit

private let uncaughtExceptionHandler: @convention(c) (NSException) -> Void = { exception in
    SimpleCrashReporter.handleException(exception)
}

private let cSignalHandler: @convention(c) (Int32) -> Void = { signal in
    SimpleCrashReporter.handleSignal(signal)
}

public class SimpleCrashReporter {

    public static func start() {
        // 1. Uncaught Exception Handler (NSException)
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)

        // 2. Signal Handlers (SIGSEGV, SIGABRT, etc.)
        signal(SIGABRT, cSignalHandler)
        signal(SIGILL, cSignalHandler)
        signal(SIGSEGV, cSignalHandler)
        signal(SIGFPE, cSignalHandler)
        signal(SIGBUS, cSignalHandler)
        signal(SIGPIPE, cSignalHandler)
        signal(SIGTRAP, cSignalHandler) // Catch Swift runtime errors (force unwrap etc.) in debug mode


        // 3. Check Previous Crash
        checkLastCrash()
    }

    fileprivate static func handleException(_ exception: NSException) {
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

        // Save crash log to disk immediately (synchronous)
        saveCrashLog(crashLog)

        // Report crash and force immediate flush (synchronous)
        AppVitalityKit.shared.handleCrashSync(report: report)
    }

    fileprivate static func handleSignal(_ signal: Int32) {
        var signalName = "Unknown"
        switch signal {
        case SIGABRT: signalName = "SIGABRT (Abort)"
        case SIGILL:  signalName = "SIGILL (Illegal Instruction)"
        case SIGSEGV: signalName = "SIGSEGV (Segmentation Fault)"
        case SIGFPE:  signalName = "SIGFPE (Floating Point Exception)"
        case SIGBUS:  signalName = "SIGBUS (Bus Error)"
        case SIGPIPE: signalName = "SIGPIPE (Broken Pipe)"
        case SIGTRAP: signalName = "SIGTRAP (Trace/Breakpoint Trap)"
        default: break
        }

        let context = generateContextSnapshot()
        let breadcrumbs = BreadcrumbLogger.shared.getLogs()
        let stack = Thread.callStackSymbols.joined(separator: "\n")

        let crashLog = """
        [CRASH REPORT - SIGNAL]
        Date: \(Date())
        Signal: \(signal) (\(signalName))

        [ENVIRONMENT]
        \(context.description)

        [BREADCRUMBS (Last Actions)]
        \(breadcrumbs.isEmpty ? "No breadcrumbs recorded." : breadcrumbs)

        [STACK TRACE]
        \(stack)
        """

        let report = AppVitalityCrashReport(
            title: signalName,
            stackTrace: stack,
            logString: crashLog,
            observedAt: Date(),
            breadcrumbs: BreadcrumbLogger.shared.getLogEntries().map { ["message": AnyEncodable($0)] },
            environment: context.data
        )

        // Save crash log to disk immediately (synchronous)
        saveCrashLog(crashLog)
        
        // Report crash and force immediate flush (synchronous)
        AppVitalityKit.shared.handleCrashSync(report: report)
        
        exit(signal)
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

        // Memory (Simple check)
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

    private static func saveCrashLog(_ log: String) {
        UserDefaults.standard.set(log, forKey: "AppVitality_LastCrashLog")
        UserDefaults.standard.synchronize()
        print("☠️ Crash log saved to disk.")
    }

    private static func checkLastCrash() {
        if let lastCrash = UserDefaults.standard.string(forKey: "AppVitality_LastCrashLog") {
            print("\n============== 🚨 PREVIOUS CRASH FOUND 🚨 ==============")
            print(lastCrash)
            print("========================================================\n")

            AppVitalityKit.shared.handleLegacyCrashLog(lastCrash)

            UserDefaults.standard.removeObject(forKey: "AppVitality_LastCrashLog")
        }
    }
}
