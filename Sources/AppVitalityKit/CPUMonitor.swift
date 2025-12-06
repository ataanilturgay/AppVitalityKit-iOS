import Foundation

public class CPUMonitor {
    
    public static let shared = CPUMonitor()
    
    private var timer: Timer?
    private let threshold: Double = 80.0 // Usage above 80% is considered "High"
    
    public func start() {
        stop()
        
        // Listen to Thermal State Changes (overheating check)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(thermalStateChanged),
                                               name: ProcessInfo.thermalStateDidChangeNotification,
                                               object: nil)
        
        // Periodic CPU measurement (every 5 seconds)
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkCPU()
        }
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func thermalStateChanged() {
        let state = ProcessInfo.processInfo.thermalState
        var stateString = "Unknown"
        
        switch state {
        case .serious:
            stateString = "Serious"
            print("🔥 THERMAL ALERT: Device is getting HOT. Performance will be throttled.")
        case .critical:
            stateString = "Critical"
            print("🔥🔥 THERMAL CRITICAL: Device is VERY HOT. App needs to cool down immediately!")
        default:
            return
        }
        
        AppVitalityKit.shared.handle(event: .thermalStateCritical(state: stateString))
    }
    
    private func checkCPU() {
        let usage = getCPUUsage()
        if usage > threshold {
            print("⚠️ HIGH CPU LOAD: \(String(format: "%.1f", usage))%. This drains battery and causes heat.")
            
            AppVitalityKit.shared.handle(event: .highCPU(usage: usage))
        }
    }
    
    // Measures CPU usage via Mach Kernel API
    private func getCPUUsage() -> Double {
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
                
                guard infoResult == KERN_SUCCESS else {
                    break
                }
                
                let threadBasicInfo = threadInfo as thread_basic_info
                if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsageOfCPU = (totalUsageOfCPU + (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0))
                }
            }
        }
        
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        return totalUsageOfCPU
    }
}

