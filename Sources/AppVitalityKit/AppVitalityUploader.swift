import Foundation
import UIKit

final class AppVitalityUploader {

    struct CloudConfig {
        let endpoint: URL
        let apiKey: String
        let flushInterval: TimeInterval
        let maxBatchSize: Int
    }
    
    // Cihaz ve Oturum Bilgileri
    private struct SessionInfo: Codable {
        let id: String
        let deviceId: String
        let appVersion: String
        let osVersion: String
        let platform: String      // "iOS"
        let model: String         // "iPhone14,3"
        let locale: String        // "en_US"
    }

    private struct EventPayload: Encodable {
        let eventType: String
        let observedAt: Date
        let payload: [String: AnyEncodable]
        let session: SessionInfo // Her event ile gönderilir
    }

    private struct CrashPayload: Codable {
        let title: String
        let stackTrace: String
        let observedAt: Date
        let breadcrumbs: [[String: AnyEncodable]]?
        let environment: [String: AnyEncodable]?
        let session: SessionInfo
    }

    private let config: CloudConfig
    private let session: URLSession
    private let encoder: JSONEncoder
    private let queue = DispatchQueue(label: "com.appvitality.uploader")
    private var eventsBuffer: [EventPayload] = []
    private var crashBuffer: [CrashPayload] = []
    private var timer: DispatchSourceTimer?
    
    // Static Session Data (Değişmezler)
    private let currentSession: SessionInfo

    init(config: CloudConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        
        // Session Bilgilerini Başlat
        self.currentSession = SessionInfo(
            id: UUID().uuidString,
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            osVersion: UIDevice.current.systemVersion,
            platform: "iOS",
            model: UIDevice.current.model, // Basit model adı (örn. "iPhone")
            locale: Locale.current.identifier
        )
        
        // Check for pending crashes from previous session
        loadPendingCrashes()
        
        startTimer()
    }

    deinit {
        timer?.cancel()
    }

    func enqueue(event: AppVitalityEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            let payload = EventPayload(
                eventType: event.type,
                observedAt: Date(),
                payload: event.toPayload(),
                session: self.currentSession
            )
            self.eventsBuffer.append(payload)
            if self.eventsBuffer.count >= self.config.maxBatchSize {
                self.flushEvents()
            }
        }
    }

    func enqueueCrash(_ log: String) {
        print("☠️ [AppVitalityKit] Enqueue crash log")
        queue.async { [weak self] in
            guard let self else { return }
            let payload = CrashPayload(
                title: "Crash Report",
                stackTrace: log,
                observedAt: Date(),
                breadcrumbs: nil,
                environment: nil,
                session: self.currentSession
            )
            // Save to disk immediately before attempting sync send
            self.saveCrashToDisk(payload)
            print("☠️ [AppVitalityKit] Crash saved to disk")
            self.crashBuffer.append(payload)
            self.flushCrashesSync()
        }
    }

    func enqueueCrashReport(title: String,
                            stackTrace: String,
                            observedAt: Date,
                            breadcrumbs: [[String: AnyEncodable]]?,
                            environment: [String: AnyEncodable]?) {
        queue.async { [weak self] in
            guard let self else { return }
            let payload = CrashPayload(
                title: title,
                stackTrace: stackTrace,
                observedAt: observedAt,
                breadcrumbs: breadcrumbs,
                environment: environment,
                session: self.currentSession
            )
            // Save to disk immediately before attempting sync send
            self.saveCrashToDisk(payload)
            self.crashBuffer.append(payload)
            self.flushCrashesSync()
        }
    }
    
    /// Synchronous crash report enqueue for signal handlers
    /// Must be called from signal handler context (no async queues)
    func enqueueCrashReportSync(title: String,
                                stackTrace: String,
                                observedAt: Date,
                                breadcrumbs: [[String: AnyEncodable]]?,
                                environment: [String: AnyEncodable]?) {
        print("☠️ [AppVitalityKit] Enqueue crash report (sync): \(title)")
        let payload = CrashPayload(
            title: title,
            stackTrace: stackTrace,
            observedAt: observedAt,
            breadcrumbs: breadcrumbs,
            environment: environment,
            session: currentSession
        )
        // Save to disk immediately (synchronous)
        saveCrashToDisk(payload)
        print("☠️ [AppVitalityKit] Crash saved to disk (sync)")
        // Try to send synchronously (with timeout)
        print("☠️ [AppVitalityKit] Attempting sync send...")
        let ok = sendSync(data: [payload], path: "/v1/crashes")
        if !ok {
            print("☠️ [AppVitalityKit] Sync send failed, will retry on next launch")
            // Failed to send, will be retried on next launch
            crashBuffer.append(payload)
        } else {
            print("☠️ [AppVitalityKit] Crash sent successfully")
            // Successfully sent, remove from disk
            removeCrashesFromDisk([payload])
        }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + config.flushInterval,
                       repeating: config.flushInterval)
        timer.setEventHandler { [weak self] in
            self?.flushEvents()
            self?.flushCrashes()
        }
        timer.resume()
        self.timer = timer
    }

    private func flushEvents() {
        guard !eventsBuffer.isEmpty else { return }
        let batch = eventsBuffer
        eventsBuffer = []
        send(data: batch, path: "/v1/events")
    }

    private func flushCrashes() {
        guard !crashBuffer.isEmpty else { return }
        let batch = crashBuffer
        crashBuffer = []
        send(data: batch, path: "/v1/crashes")
    }

    func flushCrashesSync() {
        guard !crashBuffer.isEmpty else { return }
        let batch = crashBuffer
        crashBuffer = []
        let ok = sendSync(data: batch, path: "/v1/crashes")
        if ok {
            // Successfully sent, remove from disk
            removeCrashesFromDisk(batch)
        } else {
            // Failed to send, keep in buffer and disk (already saved)
            crashBuffer.append(contentsOf: batch)
        }
    }

    private func send<T: Encodable>(data: T, path: String) {
        let sanitizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: config.endpoint.appendingPathComponent(sanitizedPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-appvitality-key")

        guard let body = try? encoder.encode(data) else { return }
        request.httpBody = body

        session.dataTask(with: request).resume()
    }

    private func sendSync<T: Encodable>(data: T, path: String) -> Bool {
        let sanitizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: config.endpoint.appendingPathComponent(sanitizedPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-appvitality-key")

        guard let body = try? encoder.encode(data) else { return false }
        request.httpBody = body

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        let task = session.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), error == nil {
                success = true
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2.0) // wait up to 2s
        return success
    }
    
    // MARK: - Disk Persistence
    
    private static let pendingCrashesKey = "AppVitality_PendingCrashes"
    
    private func saveCrashToDisk(_ payload: CrashPayload) {
        guard let encoded = try? encoder.encode(payload),
              let jsonString = String(data: encoded, encoding: .utf8) else {
            return
        }
        
        var pending = UserDefaults.standard.stringArray(forKey: Self.pendingCrashesKey) ?? []
        pending.append(jsonString)
        UserDefaults.standard.set(pending, forKey: Self.pendingCrashesKey)
        UserDefaults.standard.synchronize()
    }
    
    private func removeCrashesFromDisk(_ payloads: [CrashPayload]) {
        guard var pending = UserDefaults.standard.stringArray(forKey: Self.pendingCrashesKey),
              !pending.isEmpty else {
            return
        }
        
        // Remove successfully sent crashes
        let sentIds = Set(payloads.map { "\($0.title)-\($0.observedAt.timeIntervalSince1970)" })
        pending.removeAll { jsonString in
            guard let data = jsonString.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(CrashPayload.self, from: data) else {
                return false
            }
            let id = "\(payload.title)-\(payload.observedAt.timeIntervalSince1970)"
            return sentIds.contains(id)
        }
        
        UserDefaults.standard.set(pending, forKey: Self.pendingCrashesKey)
        UserDefaults.standard.synchronize()
    }
    
    private func loadPendingCrashes() {
        guard let pending = UserDefaults.standard.stringArray(forKey: Self.pendingCrashesKey),
              !pending.isEmpty else {
            return
        }
        
        print("☠️ [AppVitalityKit] Found \(pending.count) pending crash(es) from previous session")
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        for jsonString in pending {
            guard let data = jsonString.data(using: .utf8),
                  let payload = try? decoder.decode(CrashPayload.self, from: data) else {
                continue
            }
            crashBuffer.append(payload)
            print("☠️ [AppVitalityKit] Loaded pending crash: \(payload.title)")
        }
        
        // Try to send pending crashes immediately
        if !crashBuffer.isEmpty {
            print("☠️ [AppVitalityKit] Sending \(crashBuffer.count) pending crash(es)...")
            flushCrashes()
        }
    }
}
