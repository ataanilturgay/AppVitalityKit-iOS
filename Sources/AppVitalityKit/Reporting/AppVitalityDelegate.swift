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

