import Foundation
import UIKit

/// Provides real-time device context metrics to enrich every event
/// These metrics help understand the device state when an event occurred
public struct DeviceContext {
    
    /// Current CPU usage percentage (0-100)
    public let cpuUsage: Double
    
    /// Current memory usage in MB
    public let memoryUsageMB: Double
    
    /// Current FPS (if available, otherwise -1)
    public let fps: Double
    
    /// Thermal state (0=nominal, 1=fair, 2=serious, 3=critical)
    public let thermalState: Int
    
    /// Battery level (0-100, or -1 if unknown)
    public let batteryLevel: Int
    
    /// Whether device is charging
    public let isCharging: Bool
    
    /// Session-level frustration counters
    public let sessionRageTapCount: Int
    public let sessionDeadClickCount: Int
    
    /// Capture current device context
    public static func capture(
        sessionRageTaps: Int = 0,
        sessionDeadClicks: Int = 0,
        currentFPS: Double = -1
    ) -> DeviceContext {
        return DeviceContext(
            cpuUsage: Self.getCPUUsage(),
            memoryUsageMB: Self.getMemoryUsageMB(),
            fps: currentFPS,
            thermalState: ProcessInfo.processInfo.thermalState.rawValue,
            batteryLevel: Self.getBatteryLevel(),
            isCharging: Self.isCharging(),
            sessionRageTapCount: sessionRageTaps,
            sessionDeadClickCount: sessionDeadClicks
        )
    }
    
    /// Convert to dictionary for payload
    public func toDictionary() -> [String: AnyEncodable] {
        var dict: [String: AnyEncodable] = [
            "device_cpu": AnyEncodable(cpuUsage),
            "device_memory_mb": AnyEncodable(memoryUsageMB),
            "device_thermal_state": AnyEncodable(thermalState)
        ]
        
        if fps >= 0 {
            dict["device_fps"] = AnyEncodable(fps)
        }
        
        if batteryLevel >= 0 {
            dict["device_battery"] = AnyEncodable(batteryLevel)
            dict["device_charging"] = AnyEncodable(isCharging)
        }
        
        if sessionRageTapCount > 0 {
            dict["session_rage_taps"] = AnyEncodable(sessionRageTapCount)
        }
        
        if sessionDeadClickCount > 0 {
            dict["session_dead_clicks"] = AnyEncodable(sessionDeadClickCount)
        }
        
        return dict
    }
    
    // MARK: - Private Helpers
    
    private static func getCPUUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = withUnsafeMutablePointer(to: &threadsList) {
            return $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadsCount)
            }
        }
        
        if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
            for i in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(i)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                
                guard infoResult == KERN_SUCCESS else { break }
                
                if threadInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsageOfCPU += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                }
            }
            
            // Deallocate threads list
            let size = vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threadsList), size)
        }
        
        return min(totalUsageOfCPU, 100.0)
    }
    
    private static func getMemoryUsageMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        }
        return 0
    }
    
    private static func getBatteryLevel() -> Int {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level < 0 {
            return -1
        }
        return Int(level * 100)
    }
    
    private static func isCharging() -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }
}

