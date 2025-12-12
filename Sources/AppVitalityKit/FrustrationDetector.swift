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
    
    private var lastGhostTouchReport: Date?
    private let ghostTouchCooldown: TimeInterval = 2.0 // Don't report ghost touch too frequently
    
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
        
        // Check for ghost touch (tap on empty area)
        checkGhostTouch(at: location, hitView: hitView, screen: screen)
        
        // Check for dead click (tap on non-interactive element)
        checkDeadClick(at: location, hitView: hitView, screen: screen)
        
        // Record tap for rage detection
        recordTap(at: location, screen: screen)
        
        // Check for rage tap pattern
        checkRageTap(at: location, screen: screen)
    }
    
    // MARK: - Ghost Touch Detection
    
    private func checkGhostTouch(at location: CGPoint, hitView: UIView?, screen: String?) {
        guard let window = getKeyWindow() else { return }
        
        // Ghost touch = tap directly on window or root view (empty area)
        let isEmptyArea: Bool
        
        if hitView == nil || hitView == window {
            isEmptyArea = true
        } else if let view = hitView {
            // Check if it's a large container (covers most of screen)
            let screenBounds = window.bounds
            let viewBounds = view.bounds
            let viewArea = viewBounds.width * viewBounds.height
            let screenArea = screenBounds.width * screenBounds.height
            
            // If view covers >80% of screen and has no meaningful content
            if viewArea > screenArea * 0.8 && !isInteractiveView(view) && !looksClickable(view) {
                isEmptyArea = true
            } else {
                isEmptyArea = false
            }
        } else {
            isEmptyArea = false
        }
        
        guard isEmptyArea else { return }
        
        // Check cooldown
        if let lastReport = lastGhostTouchReport,
           Date().timeIntervalSince(lastReport) < ghostTouchCooldown {
            return
        }
        
        lastGhostTouchReport = Date()
        reportGhostTouch(at: location, screen: screen)
    }
    
    private func reportGhostTouch(at location: CGPoint, screen: String?) {
        guard let window = getKeyWindow() else { return }
        
        // Normalize coordinates to 0-100 scale
        let normalizedX = Int((location.x / window.bounds.width) * 100)
        let normalizedY = Int((location.y / window.bounds.height) * 100)
        
        // Find nearest element in background to avoid blocking main thread
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let nearest = self?.findNearestInteractiveElementAsync(from: location, in: window)
            
            DispatchQueue.main.async {
                let event = AppVitalityEvent.ghostTouch(
                    x: normalizedX,
                    y: normalizedY,
                    screen: screen,
                    nearestElement: nearest?.identifier,
                    distanceToNearest: nearest?.distance
                )
                
                AppVitalityKit.shared.handle(event: event)
                BreadcrumbLogger.shared.logAction("ghost_touch", target: "(\(normalizedX), \(normalizedY)) @ \(screen ?? "unknown")")
                print("👻 [AppVitalityKit] Ghost Touch detected at (\(normalizedX), \(normalizedY)) on \(screen ?? "unknown")")
            }
        }
    }
    
    /// Find nearest interactive element - runs on background thread
    /// Limited to first 100 interactive views to prevent excessive traversal
    private func findNearestInteractiveElementAsync(from point: CGPoint, in window: UIWindow) -> (identifier: String, distance: Int)? {
        var interactiveViews: [(view: UIView, center: CGPoint)] = []
        let maxViews = 100 // Limit to prevent performance issues
        
        // Collect interactive views (limited)
        collectInteractiveViews(in: window, into: &interactiveViews, limit: maxViews)
        
        // Find nearest
        var nearest: (identifier: String, distance: CGFloat)? = nil
        
        for item in interactiveViews {
            let dist = distance(point, item.center)
            
            if dist < 200 { // Only consider elements within 200pt
                if nearest == nil || dist < nearest!.distance {
                    let identifier = item.view.accessibilityIdentifier ??
                                    item.view.accessibilityLabel ??
                                    String(describing: type(of: item.view))
                    nearest = (identifier, dist)
                }
            }
        }
        
        return nearest.map { ($0.identifier, Int($0.distance)) }
    }
    
    /// Collect interactive views with a limit to prevent excessive traversal
    private func collectInteractiveViews(in view: UIView, into array: inout [(view: UIView, center: CGPoint)], limit: Int) {
        guard array.count < limit else { return }
        
        if isInteractiveView(view) {
            // Get center in window coordinates
            if let window = view.window {
                let center = view.superview?.convert(view.center, to: window) ?? view.center
                array.append((view, center))
            }
        }
        
        for subview in view.subviews {
            guard array.count < limit else { return }
            collectInteractiveViews(in: subview, into: &array, limit: limit)
        }
    }
    
    // MARK: - Dead Click Detection
    
    private func checkDeadClick(at location: CGPoint, hitView: UIView?, screen: String?) {
        guard let view = hitView else { 
            AppVitalityKit.shared.debugLog("Dead click check: No hit view")
            return 
        }
        
        let viewType = String(describing: type(of: view))
        let viewId = view.accessibilityIdentifier
        
        // Skip system views (private UIKit classes)
        if viewType.hasPrefix("_UI") {
            AppVitalityKit.shared.debugLog("Dead click check: \(viewType) is system view, skipping")
            return
        }
        
        // Skip if the view is interactive
        if isInteractiveView(view) {
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
        if looksClickable(view) || isLearned {
            if isLearned {
                AppVitalityKit.shared.debugLog("🧠 Dead click (learned): \(viewType) on \(screen ?? "unknown")")
            }
            reportDeadClick(view: view, location: location, screen: screen, isLearned: isLearned)
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
        
        // Get container contents for debugging
        let containerContents = describeContainerContents(view)
        
        // Send dead click event with all metadata
        let event = AppVitalityEvent.deadClick(
            viewType: viewType,
            viewId: viewId,
            screen: screen,
            elementText: extractText(from: view),
            isLearned: isLearned,
            containerContents: containerContents,
            totalTaps: tapCount
        )
        
        let learnedTag = isLearned ? " [LEARNED]" : ""
        let contentsInfo = containerContents.map { " → Contains: \($0)" } ?? ""
        print("🎯 [AppVitalityKit] Dead Click detected\(learnedTag): \(viewType) on \(screen ?? "unknown")\(contentsInfo)")
        
        AppVitalityKit.shared.handle(event: event)
        
        // Log to breadcrumbs
        BreadcrumbLogger.shared.logAction("dead_click", target: "\(viewType) @ \(screen ?? "unknown")")
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
    
    /// Describe what's inside a container view (for better debugging)
    /// Example: "UILabel('Ürün Adı'), UIImageView, UILabel('₺99')"
    private func describeContainerContents(_ view: UIView) -> String? {
        guard !view.subviews.isEmpty else { return nil }
        
        var descriptions: [String] = []
        
        for subview in view.subviews.prefix(5) { // Max 5 subviews
            let typeName = String(describing: type(of: subview))
            
            // Skip private/system views
            if typeName.hasPrefix("_") { continue }
            
            // Get text if available
            if let label = subview as? UILabel, let text = label.text, !text.isEmpty {
                let shortText = String(text.prefix(20))
                descriptions.append("\(typeName)('\(shortText)')")
            } else if let button = subview as? UIButton, let title = button.currentTitle {
                descriptions.append("\(typeName)('\(title)')")
            } else {
                descriptions.append(typeName)
            }
        }
        
        if view.subviews.count > 5 {
            descriptions.append("+\(view.subviews.count - 5) more")
        }
        
        return descriptions.isEmpty ? nil : descriptions.joined(separator: ", ")
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

