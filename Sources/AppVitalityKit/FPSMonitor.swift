import Foundation
import UIKit
import QuartzCore

public class FPSMonitor {
    
    public static let shared = FPSMonitor()
    
    private var displayLink: CADisplayLink?
    private var lastUpdateTime: TimeInterval = 0
    private var frameCount: Int = 0
    
    // Target minimum FPS (below this means "Lagging")
    private let tolerance: Double = 55.0 
    
    public func start() {
        stop()
        
        displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func tick(_ link: CADisplayLink) {
        if lastUpdateTime == 0 {
            lastUpdateTime = link.timestamp
            return
        }
        
        frameCount += 1
        let delta = link.timestamp - lastUpdateTime
        
        // Report every 1 second
        if delta >= 1.0 {
            let fps = Double(frameCount) / delta
            
            if fps < tolerance {
                // FPS Drop (Lag) Detected
                // Only meaningful during scrolling or animation,
                // but display link runs on static screens too (usually gives 60 even when idle).
                // In Low Power Mode, system can cap FPS to 30, need to differentiate this.
                
                let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                let threshold = isLowPower ? 25.0 : 55.0
                
                if fps < threshold {
                    print("⚠️ UI LAG DETECTED: \(String(format: "%.1f", fps)) FPS (Low Power: \(isLowPower))")
                    
                    AppVitalityKit.shared.handle(event: .fpsDrop(fps: fps, isLowPowerMode: isLowPower))
                }
            }
            
            frameCount = 0
            lastUpdateTime = link.timestamp
        }
    }
}

