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
        case let .custom(_, parameters):
            return parameters
        }
    }
}

