import Foundation

public class MainThreadWatchdog {

    public static let shared = MainThreadWatchdog()

    private var pingTimer: Timer?
    private let threshold: TimeInterval = 0.4 // 400ms (approximately 24 frames lost)
    private let semaphore = DispatchSemaphore(value: 0)

    // Thread-safe running state using NSLock (iOS 11+ compatible)
    private var _isRunning: Bool = false
    private let lock = NSLock()

    private var isRunning: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isRunning
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isRunning = newValue
        }
    }

    private init() {}

    public func start() {
        // Atomically check and set isRunning
        lock.lock()
        if _isRunning {
            lock.unlock()
            return
        }
        _isRunning = true
        lock.unlock()
        
        // A structure that constantly pokes the main thread from the background
        // A real watchdog should work when main thread is blocked, so Timer should not be on main thread.
        // We set up a loop on a different thread.
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            while self.isRunning {
                var mainThreadResponded = false
                
                DispatchQueue.main.async {
                    mainThreadResponded = true
                    self.semaphore.signal()
                }
                
                // Wait duration
                let result = self.semaphore.wait(timeout: .now() + self.threshold)
                
                if result == .timedOut {
                    if !mainThreadResponded {
                        // Main thread did not respond! There's a hang.
                        self.reportHang()
                        // We can wait until response arrives or next loop,
                        // but semaphore is not still locked since wait timed out.
                        // So instead of waiting again, let's sleep a bit before
                        // entering the next loop to avoid 100% CPU usage.
                    }
                }
                
                // Ping interval to prevent excessive CPU usage (e.g. check every 1 second)
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
    }
    
    public func stop() {
        isRunning = false
    }
    
    private func reportHang() {
        // This is NOT the main thread.
        print("⚠️ WATCHDOG: Main Thread blocked for > \(threshold)s! Possible UI Freeze.")
        
        // We could capture and report stack trace (Advanced feature)
        // CallStackSymbols.print() // This prints the current (background) thread, not useful.
        // Getting main thread stack trace requires more complex C code (PLCrashReporter etc.)
        // For now, we just print a warning.
        AppVitalityKit.shared.handle(event: .uiHang(duration: threshold))
    }
}

