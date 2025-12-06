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
    private struct SessionInfo: Encodable {
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

    private struct CrashPayload: Encodable {
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
            self.crashBuffer.append(payload)
            self.flushCrashesSync()
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

    private func flushCrashesSync() {
        guard !crashBuffer.isEmpty else { return }
        let batch = crashBuffer
        crashBuffer = []
        let ok = sendSync(data: batch, path: "/v1/crashes")
        if !ok {
            // put back to buffer to retry on next launch/interval
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
}
