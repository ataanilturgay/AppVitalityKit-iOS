# AppVitalityKit

iOS SDK for [AppVitality](https://github.com/your-org/AppVitality) - Mobile app analytics and performance monitoring.

## Features

- 📊 **Auto Analytics** - Screen views, button taps, session tracking
- 🔥 **Crash Reporting** - Automatic crash detection with breadcrumbs
- ⚡ **Performance Monitoring** - FPS, CPU, memory, UI hangs
- 🔋 **Battery Friendly** - Configurable power policies
- ☁️ **Cloud Sync** - Automatic batched uploads to AppVitality

## Installation

### Swift Package Manager (Recommended)

Add the package to your Xcode project:

1. **File** → **Add Package Dependencies...**
2. Enter the repository URL:
   ```
   https://github.com/your-org/AppVitalityKit-iOS
   ```
3. Select version and add to your target

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/AppVitalityKit-iOS", from: "1.0.0")
]
```

## Quick Start

### 1. Configure in AppDelegate

```swift
import AppVitalityKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, 
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Initialize with your API key from AppVitality Dashboard
        AppVitalityKit.shared.configure(
            apiKey: "your-api-key-here"
        )
        
        return true
    }
}
```

### 2. SwiftUI App

```swift
import SwiftUI
import AppVitalityKit

@main
struct MyApp: App {
    
    init() {
        AppVitalityKit.shared.configure(
            apiKey: "your-api-key-here"
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Configuration Options

```swift
AppVitalityKit.shared.configure(
    apiKey: "your-api-key",
    options: .init(
        features: [
            .autoActionTracking,  // Screen views & button taps
            .crashReporting,      // Crash detection
            .fpsMonitor,          // Frame rate monitoring
            .cpuMonitor,          // CPU usage tracking
            .memoryMonitor,       // Memory warnings
            .mainThreadWatchdog,  // UI hang detection
            .networkMonitoring,   // Network quality
            .metricKitReporting   // iOS MetricKit data
        ],
        policy: .moderate,        // .strict, .moderate, .relaxed
        flushInterval: 10,        // Seconds between uploads
        maxBatchSize: 20          // Events per batch
    )
)
```

### Feature Presets

```swift
// All features
options: .init(features: Feature.all)

// Recommended (default)
options: .init(features: Feature.recommended)

// Minimal
options: .init(features: [.crashReporting, .autoActionTracking])
```

## Auto-Tracked Events

When `.autoActionTracking` is enabled:

| Event Type | Trigger | Payload |
|------------|---------|---------|
| `screen_view` | UIViewController appears | `screen`, `previous_screen` |
| `button_tap` | UIButton tap | `button_text`, `button_id`, `screen` |
| `session_start` | App becomes active | - |
| `session_end` | App goes to background | `duration_seconds` |

### Better Button Tracking

Set `accessibilityIdentifier` for cleaner reports:

```swift
buyButton.accessibilityIdentifier = "buy_now_button"
// Dashboard shows: "buy_now_button" instead of "Buy Now"
```

## Manual Event Logging

```swift
// Custom event
AppVitalityKit.shared.log(event: "purchase_completed", parameters: [
    "product_id": AnyEncodable("SKU123"),
    "price": AnyEncodable(29.99),
    "currency": AnyEncodable("USD")
])

// Page view (if not using auto-tracking)
AppVitalityKit.shared.log(event: "page_view", parameters: [
    "screen": AnyEncodable("CheckoutScreen")
])
```

## Delegate (Optional)

Receive events locally for debugging or custom handling:

```swift
class MyAnalyticsHandler: AppVitalityDelegate {
    
    func didDetectEvent(_ event: AppVitalityEvent) {
        print("Event: \(event.type)")
    }
    
    func didDetectCrash(_ log: String) {
        print("Crash detected: \(log)")
    }
}

// Set delegate
AppVitalityKit.shared.delegate = MyAnalyticsHandler()
```

## Requirements

- iOS 13.0+
- Swift 5.5+
- Xcode 13.0+

## Privacy

AppVitalityKit collects:
- Device model, OS version
- App version
- Anonymous device identifier (vendor ID)
- Screen names and button interactions
- Performance metrics (FPS, CPU, memory)
- Crash stack traces

**No personal data is collected.** See [Privacy Policy](https://appvitality.io/privacy).

## License

MIT License - see [LICENSE](LICENSE) for details.
