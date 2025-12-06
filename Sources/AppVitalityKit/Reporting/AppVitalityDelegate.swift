import Foundation

/// Protocol that enables exporting data collected by the SDK.
/// Developers can implement this protocol to send data to their own analytics system (Firebase, Sentry, etc.).
public protocol AppVitalityDelegate: AnyObject {
    
    /// Triggered when a critical event is detected.
    /// - Parameter event: Type and detail of the event.
    func didDetectEvent(_ event: AppVitalityEvent)
    
    /// Triggered if a crash occurred in the previous session.
    /// - Parameter log: Crash report (Stack trace, environment info, etc.)
    func didDetectCrash(_ log: String)
}

public enum AppVitalityEvent {
    /// FPS drop (UI Lag)
    case fpsDrop(fps: Double, isLowPowerMode: Bool)
    
    /// High CPU usage
    case highCPU(usage: Double)
    
    /// Device overheating
    case thermalStateCritical(state: String)
    
    /// Inefficient network usage (Background Fetch, etc.)
    case inefficientNetwork(url: String, reason: String)
    
    /// Main thread freeze (Hang)
    case uiHang(duration: TimeInterval)
    
    /// High Memory Usage
    case highMemory(usedMB: Double)
}

