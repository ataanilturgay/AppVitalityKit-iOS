import UIKit

extension UIControl {
    
    static func enableActionTracking() {
        Swizzler.swizzle(UIControl.self,
                         originalSelector: #selector(sendAction(_:to:for:)),
                         swizzledSelector: #selector(bf_sendAction(_:to:for:)))
    }
    
    @objc private func bf_sendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
        // Call original method
        bf_sendAction(action, to: target, for: event)
        
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
        
        // Log breadcrumb for crash debugging
        var logMessage = "UI Action: \(String(describing: action))"
        if let identifier = buttonId {
            logMessage += " | Target: \(identifier)"
        } else {
            logMessage += " | Class: \(String(describing: type(of: self)))"
            if let title = buttonText {
                logMessage += " | Title: '\(title)'"
            }
        }
        BreadcrumbLogger.shared.log(logMessage)
        
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
}

