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
        
        // Determine if this is a critical action
        let isCritical = isCriticalAction(buttonId: buttonId, buttonText: buttonText, action: action)
        
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
        
        // Log to breadcrumbs
        if isCritical {
            BreadcrumbLogger.shared.logCritical("👆 \(logMessage)")
        } else {
            BreadcrumbLogger.shared.logAction("tap", target: logMessage)
        }
        
        // Send button_tap event for analytics (only for meaningful taps)
        if buttonText != nil || buttonId != nil {
            let tapEvent = AppVitalityEvent.buttonTap(
                buttonText: buttonText,
                buttonId: buttonId,
                screen: currentScreen
            )
            AppVitalityKit.shared.handle(event: tapEvent)
        }
    }
    
    /// Determines if an action should be treated as critical (immediately persisted).
    /// Critical actions: payments, auth, destructive actions, navigation
    private func isCriticalAction(buttonId: String?, buttonText: String?, action: Selector) -> Bool {
        let actionName = NSStringFromSelector(action).lowercased()
        let id = buttonId?.lowercased() ?? ""
        let text = buttonText?.lowercased() ?? ""
        
        // Keywords that indicate critical actions
        let criticalKeywords = [
            // Payment & Purchase
            "pay", "purchase", "buy", "checkout", "order", "subscribe",
            // Authentication
            "login", "logout", "signin", "signout", "register", "signup", "auth",
            // Destructive
            "delete", "remove", "cancel", "clear", "reset",
            // Important navigation
            "submit", "confirm", "save", "send", "share", "post",
            // Settings
            "setting", "preference", "permission"
        ]
        
        for keyword in criticalKeywords {
            if actionName.contains(keyword) ||
               id.contains(keyword) ||
               text.contains(keyword) {
                return true
            }
        }
        
        return false
    }
}
