import UIKit

extension UIViewController {
    
    // Store the previous screen name for analytics
    private static var _previousScreen: String?
    private static var previousScreen: String? {
        get { _previousScreen }
        set { _previousScreen = newValue }
    }
    
    static func enableLifecycleTracking() {
        Swizzler.swizzle(UIViewController.self,
                         originalSelector: #selector(viewDidAppear(_:)),
                         swizzledSelector: #selector(av_viewDidAppear(_:)))
    }
    
    @objc private func av_viewDidAppear(_ animated: Bool) {
        // Call original method (due to swizzling logic, this actually calls the original)
        av_viewDidAppear(animated)
        
        // We only care about our own screens (exclude system view controllers)
        let screenName = String(describing: type(of: self))
        
        // Filter out system classes like UIInputWindowController
        if !screenName.hasPrefix("UI") && !screenName.hasPrefix("_") {
            // Notify SDK of screen change for Critical Path Detection
            AppVitalityKit.shared.onScreenChanged(screenName)
            
            // Log breadcrumb for crash debugging (CRITICAL - persisted immediately)
            BreadcrumbLogger.shared.logScreenView(screenName)
            
            // Send screen_view event for analytics
            let event = AppVitalityEvent.screenView(
                screen: screenName,
                previousScreen: UIViewController.previousScreen
            )
            AppVitalityKit.shared.handle(event: event)
            
            // Update previous screen
            UIViewController.previousScreen = screenName
        }
    }
}

