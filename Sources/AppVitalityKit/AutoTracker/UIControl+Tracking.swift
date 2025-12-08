import UIKit

extension UIControl {
    
    static func enableActionTracking() {
        Swizzler.swizzle(UIControl.self,
                         originalSelector: #selector(sendAction(_:to:for:)),
                         swizzledSelector: #selector(av_sendAction(_:to:for:)))
    }
    
    @objc private func av_sendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
        // Call original method
        av_sendAction(action, to: target, for: event)
        
        // Extract button info
        let buttonId = self.accessibilityIdentifier
        var buttonText: String? = nil
        
        // If it's a button, try to get its title
        if let button = self as? UIButton {
            buttonText = button.currentTitle
        }
        
        // Get current screen name from responder chain
        var currentScreen: String? = nil
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController {
                let screenName = String(describing: type(of: vc))
                if !screenName.hasPrefix("UI") && !screenName.hasPrefix("_") {
                    currentScreen = screenName
                    break
                }
            }
            responder = r.next
        }
        
        // Build log message
        let actionName = NSStringFromSelector(action)
        var logParts: [String] = [actionName]
        
        if let id = buttonId {
            logParts.append("id:\(id)")
        }
        if let text = buttonText {
            logParts.append("'\(text)'")
        }
        if let screen = currentScreen {
            logParts.append("@\(screen)")
        }
        
        let logMessage = logParts.joined(separator: " | ")
        
        // Log to breadcrumbs only (not sent as separate events)
        // Button taps are captured as breadcrumbs and included in crash reports
        // On critical screens: immediately persist (won't be lost on crash)
        if AppVitalityKit.shared.isCriticalScreen(currentScreen ?? "") {
            BreadcrumbLogger.shared.logCritical("👆 \(logMessage)")
        } else {
            BreadcrumbLogger.shared.logAction("tap", target: logMessage)
        }
    }
}
