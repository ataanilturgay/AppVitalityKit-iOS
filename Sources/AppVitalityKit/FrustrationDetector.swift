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
            
            print("😤 [AppVitalityKit] FrustrationDetector: Gesture recognizer installed on window")
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
    
    /// Find the most relevant visual element at a tap point.
    /// When hit testing returns a container (UIStackView, UIView), we look for the actual
    /// visual element (UILabel, UIImageView) that the user was trying to tap.
    private func findVisualElement(in view: UIView, at point: CGPoint) -> UIView {
        let viewType = String(describing: type(of: view))
        
        // If it's already a specific visual element, return it
        let visualTypes = ["UILabel", "UIImageView", "UITextView", "UITextField", "UIButton"]
        if visualTypes.contains(viewType) {
            return view
        }
        
        // If it's a container, look for visual elements in subviews at this point
        let pointInView = view.convert(point, from: view.window)
        
        for subview in view.subviews.reversed() {
            // Check if the tap point is within this subview
            let pointInSubview = subview.convert(point, from: view.window)
            if subview.bounds.contains(pointInSubview) && !subview.isHidden && subview.alpha > 0 {
                let subviewType = String(describing: type(of: subview))
                
                // If subview is a visual element, return it
                if visualTypes.contains(subviewType) {
                    AppVitalityKit.shared.debugLog("Found visual element: \(subviewType) inside \(viewType)")
                    return subview
                }
                
                // Recursively search in subview
                let found = findVisualElement(in: subview, at: point)
                if found !== subview {
                    return found
                }
            }
        }
        
        // No visual element found, return original view
        return view
    }
    
    private func checkDeadClick(at location: CGPoint, hitView: UIView?, screen: String?) {
        guard let view = hitView else { 
            AppVitalityKit.shared.debugLog("Dead click check: No hit view")
            return 
        }
        
        // Find the actual visual element the user was trying to tap
        let targetView = findVisualElement(in: view, at: location)
        
        let viewType = String(describing: type(of: targetView))
        let viewId = targetView.accessibilityIdentifier
        
        // Skip system views (private UIKit classes)
        if viewType.hasPrefix("_UI") {
            AppVitalityKit.shared.debugLog("Dead click check: \(viewType) is system view, skipping")
            return
        }
        
        // Skip if the view is interactive
        if isInteractiveView(targetView) {
            AppVitalityKit.shared.debugLog("Dead click check: \(viewType) is interactive, skipping")
            return
        }
        
        // 🧠 AUTO-LEARNING: Record this tap for pattern learning
        // Even if we don't report it as dead click now, we're learning
        let isLearned = TapPatternLearner.shared.recordTap(
            viewType: viewType,
            screen: screen,
            viewId: viewId
        )
        
        // Check if it looks like the user expected interactivity:
        // 1. Heuristic rules (blue label, bordered view, etc.)
        // 2. OR learned from user behavior (many users tapped this)
        if looksClickable(targetView) || isLearned {
            if isLearned {
                AppVitalityKit.shared.debugLog("🧠 Dead click (learned): \(viewType) on \(screen ?? "unknown")")
            }
            reportDeadClick(view: targetView, location: location, screen: screen, isLearned: isLearned)
        } else {
            let tapCount = TapPatternLearner.shared.getTapCount(viewType: viewType, screen: screen, viewId: viewId)
            AppVitalityKit.shared.debugLog("Dead click check: \(viewType) doesn't look clickable (tap count: \(tapCount)/5)")
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
                AppVitalityKit.shared.debugLog("looksClickable: UIImageView with size \(view.bounds.width)x\(view.bounds.height)")
                return true
            }
        }
        
        // UILabel that looks like a link
        if let label = view as? UILabel {
            // Check for link-like text color (blue-ish)
            if let textColor = label.textColor {
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
                textColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
                // Blue color: more blue than red and green
                if blue > 0.5 && blue > red && blue > green {
                    AppVitalityKit.shared.debugLog("looksClickable: UILabel with blue text color")
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
    
    private func reportDeadClick(view: UIView, location: CGPoint, screen: String?, isLearned: Bool = false) {
        let viewType = String(describing: type(of: view))
        let viewId = view.accessibilityIdentifier
        
        // Get tap count for context
        let tapCount = TapPatternLearner.shared.getTapCount(viewType: viewType, screen: screen, viewId: viewId)
        
        var details: [String: AnyEncodable] = [
            "view_type": AnyEncodable(viewType),
            "location_x": AnyEncodable(Int(location.x)),
            "location_y": AnyEncodable(Int(location.y)),
            "is_learned": AnyEncodable(isLearned),
            "total_taps": AnyEncodable(tapCount)
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
        
        let learnedTag = isLearned ? " [LEARNED]" : ""
        print("🎯 [AppVitalityKit] Dead Click detected\(learnedTag): \(viewType) on \(screen ?? "unknown")")
        
        AppVitalityKit.shared.handle(event: event)
        
        // Log to breadcrumbs
        BreadcrumbLogger.shared.logAction("dead_click", target: "\(viewType) @ \(screen ?? "unknown")")
        
        print("🎯 [AppVitalityKit] Dead Click detected: \(viewType) on \(screen ?? "unknown")")
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
        
        print("😤 [AppVitalityKit] Rage Tap detected: \(tapCount) taps in \(rageTapTimeWindow)s on \(screen ?? "unknown")")
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

