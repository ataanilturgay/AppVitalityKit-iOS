import Foundation

public class MemoryMonitor {
    
    public static let shared = MemoryMonitor()
    
    private var timer: Timer?
    private let memoryLimitBytes: UInt64 = 500 * 1024 * 1024 // 500 MB (Example Limit)
    
    public func start() {
        stop()
        // Check every 30 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkMemoryUsage()
        }
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkMemoryUsage() {
        let usedBytes = getMemoryUsage()
        
        if usedBytes > memoryLimitBytes {
            let usedMB = Double(usedBytes) / 1024 / 1024
            print("⚠️ MEMORY WARNING: App is using \(String(format: "%.2f", usedMB)) MB RAM.")
            
            AppVitalityKit.shared.handle(event: .highMemory(usedMB: usedMB))
        }
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return info.resident_size
        } else {
            return 0
        }
    }
}

