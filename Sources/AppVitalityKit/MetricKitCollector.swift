import Foundation
import MetricKit

@available(iOS 13.0, *)
public class MetricKitCollector: NSObject {
    public static let shared = MetricKitCollector()
    
    public override init() {
        super.init()
        MXMetricManager.shared.add(self)
    }
    
    deinit {
        MXMetricManager.shared.remove(self)
    }
    
    // Simulating sending to a dashboard
    private func sendToDashboard(_ payload: MXMetricPayload) {
        print("MetricKitCollector: Received payload for date range: \(payload.timeStampBegin) - \(payload.timeStampEnd)")
        
        if let cpuMetrics = payload.cpuMetrics {
            print("MetricKitCollector: CPU Time: \(cpuMetrics.cumulativeCPUTime)")
        }
        
        if let diskMetrics = payload.diskIOMetrics {
            print("MetricKitCollector: Disk Writes: \(diskMetrics.cumulativeLogicalWrites)")
        }
        
        // Here you would serialize and send to your backend
    }
}

@available(iOS 13.0, *)
extension MetricKitCollector: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            sendToDashboard(payload)
        }
    }
    
    @available(iOS 14.0, *)
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            print("MetricKitCollector: Received diagnostic payload: \(payload)")
        }
    }
}

