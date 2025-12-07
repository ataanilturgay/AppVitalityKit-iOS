import UIKit

/// Detects user frustration patterns: Rage Taps and Dead Clicks
/// - Rage Tap: Multiple rapid taps in the same area (indicates frustration)
/// - Dead Click: Tap on non-interactive element (indicates UX confusion)
public final class FrustrationDetector {
    
    public static let shared = FrustrationDetector()
    
    // MARK: - Configuration
    
    /// Number of taps required to trigger rage tap detection
    private let rageTapThreshold = 4
    
    /// Time window for rage tap detection (seconds)
    private let rageTapTimeWindow: TimeInterval = 2.0
    
    /// Maximum distance between taps to be considered "same area" (points)
    private let rageTapRadius: CGFloat = 60.0
    
    // MARK: - State
    
    private var recentTaps: [(location: CGPoint, timestamp: Date, screen: String?)] = []
    private let tapLock = NSLock()
    
    private var lastRageTapReport: Date?
    private let rageTapCooldown: TimeInterval = 5.0 // Don't report same rage tap within 5 seconds
    
    private init() {
        setupGestureRecognizer()
    }
    
    // MARK: - Setup
    
    private func setupGestureRecognizer() {
        DispatchQueue.main.async {
            guard let window = self.getKeyWindow() else {
                // Retry after app launches
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.setupGestureRecognizer()
                }
                return
            }
            
            let tapGesture = FrustrationTapGestureRecognizer(target: self, action: #selector(self.handleTap(_:)))
            tapGesture.cancelsTouchesInView = false
            tapGesture.delaysTouchesBegan = false
            tapGesture.delaysTouchesEnded = false
            window.addGestureRecognizer(tapGesture)
            
            AppVitalityKit.shared.debugLog("FrustrationDetector: Gesture recognizer installed")
        }
    }
    
    private func getKeyWindow() -> UIWindow? {
        if #available(iOS 15.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            return UIApplication.shared.windows.first { $0.isKeyWindow }
        }
    }
    
    // MARK: - Tap Handling
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        let location = gesture.location(in: gesture.view)
        let screen = getCurrentScreen()
        let hitView = gesture.view?.hitTest(location, with: nil)
        
        // Check for dead click (tap on non-interactive element)
        checkDeadClick(at: location, hitView: hitView, screen: screen)
        
        // Record tap for rage detection
        recordTap(at: location, screen: screen)
        
        // Check for rage tap pattern
        checkRageTap(at: location, screen: screen)
    }
    
    // MARK: - Dead Click Detection
    
    private func checkDeadClick(at location: CGPoint, hitView: UIView?, screen: String?) {
        guard let view = hitView else { return }
        
        // Skip if the view is interactive
        if isInteractiveView(view) {
            return
        }
        
        // Check if it looks like the user expected interactivity
        // (e.g., tapped on a label that looks like a button, or an image)
        if looksClickable(view) {
            reportDeadClick(view: view, location: location, screen: screen)
        }
    }
    
    private func isInteractiveView(_ view: UIView) -> Bool {
        // Check common interactive types
        if view is UIControl { return true }
        if view is UITableViewCell { return true }
        if view is UICollectionViewCell { return true }
        
        // Check gesture recognizers
        if let gestures = view.gestureRecognizers, !gestures.isEmpty {
            for gesture in gestures {
                if gesture is UITapGestureRecognizer { return true }
                if gesture is UILongPressGestureRecognizer { return true }
            }
        }
        
        // Check if it's inside a control
        var superview = view.superview
        while let sv = superview {
            if sv is UIControl { return true }
            if sv is UITableViewCell { return true }
            if sv is UICollectionViewCell { return true }
            superview = sv.superview
        }
        
        return false
    }
    
    private func looksClickable(_ view: UIView) -> Bool {
        // UIImageView - often expected to be tappable
        if view is UIImageView {
            // Check if it has meaningful size (not tiny icons)
            if view.bounds.width > 30 && view.bounds.height > 30 {
                return true
            }
        }
        
        // UILabel that looks like a link
        if let label = view as? UILabel {
            // Check for link-like text color (blue)
            if let textColor = label.textColor {
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                textColor.getHue(&hue, saturation: &saturation, brightness: nil, alpha: nil)
                // Blue-ish color
                if hue > 0.55 && hue < 0.7 && saturation > 0.3 {
                    return true
                }
            }
            
            // Check for underlined text
            if let attributedText = label.attributedText {
                var hasUnderline = false
                attributedText.enumerateAttribute(.underlineStyle, in: NSRange(location: 0, length: attributedText.length)) { value, _, _ in
                    if value != nil {
                        hasUnderline = true
                    }
                }
                if hasUnderline { return true }
            }
        }
        
        // View with border that looks like a button
        if view.layer.borderWidth > 0 && view.layer.cornerRadius > 0 {
            return true
        }
        
        // View with shadow (often cards/buttons)
        if view.layer.shadowOpacity > 0 && view.layer.cornerRadius > 0 {
            return true
        }
        
        return false
    }
    
    private func reportDeadClick(view: UIView, location: CGPoint, screen: String?) {
        let viewType = String(describing: type(of: view))
        let viewId = view.accessibilityIdentifier
        
        var details: [String: AnyEncodable] = [
            "view_type": AnyEncodable(viewType),
            "location_x": AnyEncodable(Int(location.x)),
            "location_y": AnyEncodable(Int(location.y))
        ]
        
        if let id = viewId {
            details["view_id"] = AnyEncodable(id)
        }
        if let screen = screen {
            details["screen"] = AnyEncodable(screen)
        }
        if let text = extractText(from: view) {
            details["element_text"] = AnyEncodable(text)
        }
        
        // Send dead click event
        let event = AppVitalityEvent.deadClick(
            viewType: viewType,
            viewId: viewId,
            screen: screen,
            elementText: extractText(from: view)
        )
        AppVitalityKit.shared.handle(event: event)
        
        // Log to breadcrumbs
        BreadcrumbLogger.shared.logAction("dead_click", target: "\(viewType) @ \(screen ?? "unknown")")
        
        AppVitalityKit.shared.debugLog("🎯 Dead Click detected: \(viewType) on \(screen ?? "unknown")")
    }
    
    private func extractText(from view: UIView) -> String? {
        if let label = view as? UILabel {
            return label.text?.prefix(50).description
        }
        if let button = view as? UIButton {
            return button.currentTitle
        }
        if let textView = view as? UITextView {
            return textView.text?.prefix(50).description
        }
        return view.accessibilityLabel?.prefix(50).description
    }
    
    // MARK: - Rage Tap Detection
    
    private func recordTap(at location: CGPoint, screen: String?) {
        tapLock.lock()
        defer { tapLock.unlock() }
        
        let now = Date()
        
        // Remove old taps outside time window
        recentTaps = recentTaps.filter { now.timeIntervalSince($0.timestamp) < rageTapTimeWindow }
        
        // Add new tap
        recentTaps.append((location: location, timestamp: now, screen: screen))
    }
    
    private func checkRageTap(at location: CGPoint, screen: String?) {
        tapLock.lock()
        let taps = recentTaps
        tapLock.unlock()
        
        // Count taps in the same area
        let nearbyTaps = taps.filter { distance($0.location, location) < rageTapRadius }
        
        if nearbyTaps.count >= rageTapThreshold {
            // Check cooldown to avoid duplicate reports
            if let lastReport = lastRageTapReport,
               Date().timeIntervalSince(lastReport) < rageTapCooldown {
                return
            }
            
            reportRageTap(tapCount: nearbyTaps.count, location: location, screen: screen)
            
            lastRageTapReport = Date()
            
            // Clear taps to prevent immediate re-trigger
            tapLock.lock()
            recentTaps.removeAll()
            tapLock.unlock()
        }
    }
    
    private func reportRageTap(tapCount: Int, location: CGPoint, screen: String?) {
        let event = AppVitalityEvent.rageTap(
            tapCount: tapCount,
            timeWindowSeconds: rageTapTimeWindow,
            screen: screen
        )
        AppVitalityKit.shared.handle(event: event)
        
        // Log critical breadcrumb
        BreadcrumbLogger.shared.logCritical("😤 Rage Tap: \(tapCount) taps @ \(screen ?? "unknown")")
        
        AppVitalityKit.shared.debugLog("😤 Rage Tap detected: \(tapCount) taps in \(rageTapTimeWindow)s on \(screen ?? "unknown")")
    }
    
    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }
    
    // MARK: - Helpers
    
    private func getCurrentScreen() -> String? {
        guard let window = getKeyWindow(),
              let rootVC = window.rootViewController else { return nil }
        
        return findTopViewController(from: rootVC).map { String(describing: type(of: $0)) }
    }
    
    private func findTopViewController(from vc: UIViewController) -> UIViewController? {
        if let presented = vc.presentedViewController {
            return findTopViewController(from: presented)
        }
        if let nav = vc as? UINavigationController {
            return nav.visibleViewController.flatMap { findTopViewController(from: $0) } ?? nav
        }
        if let tab = vc as? UITabBarController {
            return tab.selectedViewController.flatMap { findTopViewController(from: $0) } ?? tab
        }
        return vc
    }
}

// MARK: - Custom Gesture Recognizer

/// A tap gesture recognizer that doesn't interfere with other gestures
private class FrustrationTapGestureRecognizer: UITapGestureRecognizer {
    
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    
    override func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    
    override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

