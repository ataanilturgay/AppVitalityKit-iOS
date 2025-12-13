import Foundation

public enum AppVitalityEvent {
    // Performance Events
    case fpsDrop(fps: Double, isLowPowerMode: Bool)
    case highCPU(usage: Double)
    case thermalStateCritical(state: Int, label: String?)
    case inefficientNetwork(url: String, reason: String)
    case uiHang(duration: Double)
    case highMemory(usedMB: Double)
    
    // Analytics Events
    case screenView(screen: String, previousScreen: String?)
    case buttonTap(buttonText: String?, buttonId: String?, screen: String?)
    case sessionStart
    case sessionEnd(duration: TimeInterval)
    
    // Frustration Events (User Experience)
    case rageTap(tapCount: Int, timeWindowSeconds: Double, screen: String?)
    case deadClick(viewType: String, viewId: String?, screen: String?, elementText: String?, isLearned: Bool = false, containerContents: String? = nil, totalTaps: Int = 0)
    case ghostTouch(x: Int, y: Int, screen: String?, nearestElement: String?, distanceToNearest: Int?)
    
    // Stress Detection Events
    case stressLevelChange(level: String, score: Int, samplingMultiplier: Double)
    
    // Custom Events
    case custom(name: String, parameters: [String: AnyEncodable])
}

extension AppVitalityEvent {
    var type: String {
        switch self {
        case .fpsDrop: return "fpsDrop"
        case .highCPU: return "highCPU"
        case .thermalStateCritical: return "thermalStateCritical"
        case .inefficientNetwork: return "inefficientNetwork"
        case .uiHang: return "uiHang"
        case .highMemory: return "highMemory"
        case .screenView: return "screen_view"
        case .buttonTap: return "button_tap"
        case .sessionStart: return "session_start"
        case .sessionEnd: return "session_end"
        case .rageTap: return "rage_tap"
        case .deadClick: return "dead_click"
        case .ghostTouch: return "ghost_touch"
        case .stressLevelChange: return "stress_level_change"
        case .custom(let name, _): return name
        }
    }

    func toPayload() -> [String: AnyEncodable] {
        switch self {
        case let .fpsDrop(fps, isLowPowerMode):
            return ["fps": AnyEncodable(fps), "isLowPowerMode": AnyEncodable(isLowPowerMode)]
        case let .highCPU(usage):
            return ["usage": AnyEncodable(usage)]
        case let .thermalStateCritical(state, label):
            var payload: [String: AnyEncodable] = ["state": AnyEncodable(state)]
            if let label = label {
                payload["state_label"] = AnyEncodable(label)
            }
            return payload
        case let .inefficientNetwork(url, reason):
            return ["url": AnyEncodable(url), "reason": AnyEncodable(reason)]
        case let .uiHang(duration):
            return ["duration": AnyEncodable(duration)]
        case let .highMemory(usedMB):
            return ["usedMB": AnyEncodable(usedMB)]
        case let .screenView(screen, previousScreen):
            var payload: [String: AnyEncodable] = ["screen": AnyEncodable(screen)]
            if let prev = previousScreen {
                payload["previous_screen"] = AnyEncodable(prev)
            }
            return payload
        case let .buttonTap(buttonText, buttonId, screen):
            var payload: [String: AnyEncodable] = [:]
            if let text = buttonText {
                payload["button_text"] = AnyEncodable(text)
            }
            if let id = buttonId {
                payload["button_id"] = AnyEncodable(id)
            }
            if let scr = screen {
                payload["screen"] = AnyEncodable(scr)
            }
            return payload
        case .sessionStart:
            return [:]
        case let .sessionEnd(duration):
            return ["duration_seconds": AnyEncodable(duration)]
        case let .rageTap(tapCount, timeWindowSeconds, screen):
            var payload: [String: AnyEncodable] = [
                "tap_count": AnyEncodable(tapCount),
                "time_window_seconds": AnyEncodable(timeWindowSeconds)
            ]
            if let scr = screen {
                payload["screen"] = AnyEncodable(scr)
            }
            return payload
        case let .deadClick(viewType, viewId, screen, elementText, isLearned, containerContents, totalTaps):
            var payload: [String: AnyEncodable] = [
                "view_type": AnyEncodable(viewType),
                "is_learned": AnyEncodable(isLearned),
                "total_taps": AnyEncodable(totalTaps)
            ]
            if let id = viewId {
                payload["view_id"] = AnyEncodable(id)
            }
            if let scr = screen {
                payload["screen"] = AnyEncodable(scr)
            }
            if let text = elementText {
                payload["element_text"] = AnyEncodable(text)
            }
            if let contents = containerContents {
                payload["container_contents"] = AnyEncodable(contents)
            }
            return payload
        case let .ghostTouch(x, y, screen, nearestElement, distanceToNearest):
            var payload: [String: AnyEncodable] = [
                "x": AnyEncodable(x),
                "y": AnyEncodable(y)
            ]
            if let scr = screen {
                payload["screen"] = AnyEncodable(scr)
            }
            if let nearest = nearestElement {
                payload["nearestElement"] = AnyEncodable(nearest)
            }
            if let distance = distanceToNearest {
                payload["distanceToNearest"] = AnyEncodable(distance)
            }
            return payload
        case let .stressLevelChange(level, score, samplingMultiplier):
            return [
                "level": AnyEncodable(level),
                "score": AnyEncodable(score),
                "samplingMultiplier": AnyEncodable(samplingMultiplier)
            ]
        case let .custom(_, parameters):
            return parameters
        }
    }
}

