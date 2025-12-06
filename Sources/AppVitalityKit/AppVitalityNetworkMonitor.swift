import Foundation
import UIKit

/// This protocol can be injected into existing URLSession or Alamofire configurations
/// to monitor network traffic and report on energy consumption.
/// - Note: By default, it does NOT BLOCK requests (Monitor Only).
public class AppVitalityNetworkMonitor: URLProtocol {
    
    public static var configuration = Configuration()
    
    public struct Configuration {
        /// Whether requests should be automatically cancelled in low power mode
        /// - Warning: Setting this to 'true' is risky (should remain 'false' for Monitor Only).
        public var blockRequestsInLowPowerMode = false
        
        /// Whether requests should be blocked in the background
        /// - Warning: Setting this to 'true' is risky (should remain 'false' for Monitor Only).
        public var blockRequestsInBackground = false
        
        /// Whether to log to console on violations
        public var verboseLogging = true
        
        public init() {}
    }
    
    public override class func canInit(with request: URLRequest) -> Bool {
        // Only http/https
        guard let scheme = request.url?.scheme,
              ["http", "https"].contains(scheme) else { return false }
        
        // Don't intercept requests we've already handled (infinite loop protection)
        if URLProtocol.property(forKey: "AppVitalityHandled", in: request) != nil {
            return false
        }
        
        return true
    }
    
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    public override func startLoading() {
        // MONITORING: Only check status and warn, but don't block.
        checkAndReportEnergyImpact()
        
        // Pass the request through as-is
        guard let newRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else { return }
        URLProtocol.setProperty(true, forKey: "AppVitalityHandled", in: newRequest)
        
        let task = URLSession.shared.dataTask(with: newRequest as URLRequest) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }
            
            if let response = response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
            }
            
            if let data = data {
                self.client?.urlProtocol(self, didLoad: data)
            }
            
            self.client?.urlProtocolDidFinishLoading(self)
        }
        task.resume()
    }
    
    public override func stopLoading() {
        // Cleanup if needed
    }
    
    private func checkAndReportEnergyImpact() {
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let isBackground = UIApplication.shared.applicationState == .background
        
        // Only warn for GET requests (POST/PUT are usually critical)
        guard let method = request.httpMethod?.uppercased(),
              ["GET", "HEAD"].contains(method) else {
            return
        }
        
        var warningMessage: String?
        
        if isBackground {
            warningMessage = "⚠️ ENERGY ALERT: Background Data Fetch detected! URL: \(request.url?.absoluteString ?? "")"
        } else if isLowPower {
            warningMessage = "⚠️ ENERGY ALERT: Low Power Mode Fetch detected! URL: \(request.url?.absoluteString ?? "")"
        }
        
        if let message = warningMessage, AppVitalityNetworkMonitor.configuration.verboseLogging {
            print(message)
            
            AppVitalityKit.shared.handle(event: .inefficientNetwork(url: request.url?.absoluteString ?? "Unknown",
                                                                    reason: isBackground ? "Background Fetch" : "Low Power Mode"))
        }
    }
}
