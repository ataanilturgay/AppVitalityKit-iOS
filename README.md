# AppVitalityKit (iOS)

The official iOS SDK for [AppVitality](https://appvitality.io) - The intelligent analytics and UX monitoring platform.

**Lightweight** | **Battery Efficient** | **Privacy-First**

## Features

| Feature | Description |
|---------|-------------|
| 📊 **Auto Analytics** | Screen views, sessions, button taps |
| 💥 **Crash Reporting** | Stack traces, breadcrumbs, MetricKit integration |
| ⚡ **Performance Monitoring** | FPS, CPU, Memory, Thermal State |
| 🐌 **UI Hang Detection** | Main thread blocking detection |
| 😤 **Rage Tap Detection** | Rapid tapping indicates frustration |
| 🎯 **Dead Click Detection** | Taps on non-interactive elements |
| 👻 **Ghost Touch Detection** | Taps on empty/non-UI areas |
| 🧠 **Tap Pattern Learning** | Auto-learns expected interactive elements |
| 🚨 **User Risk Score** | Dynamic frustration detection (0-100) |
| 🎯 **Critical Screen Detection** | 100% capture on business-critical screens |
| 📈 **Adaptive Sampling** | Device & battery-aware auto-tuning |
| 🔋 **Battery Friendly** | Auto-adjusts based on battery/thermal state |

## Installation

### Swift Package Manager (Recommended)

1. **File** → **Add Package Dependencies...**
2. Enter:
   ```
   https://github.com/appvitality/AppVitalityKit-iOS
   ```
3. Select version `1.0.0` or higher

### CocoaPods

```ruby
pod 'AppVitalityKit', '~> 1.0'
```

## Quick Start

### AppDelegate

```swift
import AppVitalityKit

func application(_ application: UIApplication, 
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    
    AppVitalityKit.shared.configure(apiKey: "your-api-key")
    
    return true
}
```

That's it! The SDK automatically tracks sessions, screens, crashes, and performance.

## UX Intelligence Features

### 😤 Frustration Detection

Automatic detection of UX friction patterns:

| Signal | What It Detects | Risk Score Impact |
|--------|-----------------|-------------------|
| **Rage Tap** | 4+ rapid taps in same area within 2s | +15 |
| **Dead Click** | Tap on non-interactive view that looks clickable | +10 |
| **Ghost Touch** | Tap on completely empty area (window/root view) | +5 |
| **UI Hang** | Main thread blocked (watchdog detection) | +10 |
| **Crash** | App crash | +20 |

```swift
// All detected automatically - no code needed!
// Events sent: rage_tap, dead_click, ghost_touch, uiHang
```

### 🧠 Tap Pattern Learning

The SDK learns from user behavior:

- Tracks which views users repeatedly tap
- After 5+ users tap the same non-interactive view, it's marked as "expected to be clickable"
- Provides `isLearned` flag in dead click events

### 🚨 User Risk Score

Dynamic risk assessment per session:

| Score | Level | Behavior |
|-------|-------|----------|
| 0-39 | Low | Normal sampling |
| 40-69 | Medium | Increased capture |
| 70-100 | High | **100% event capture** |

### 🎯 Critical Screen Detection

Ensure 100% data capture on important screens:

```swift
AppVitalityKit.shared.markCriticalScreens([
    "PaymentConfirmViewController",
    "CheckoutFinalViewController",
    "SubscriptionPurchaseVC"
])

// Check if current screen is critical
if AppVitalityKit.shared.isCriticalScreen("PaymentVC") {
    // Full capture mode active
}
```

## Manual Tracking

```swift
// Custom event
AppVitalityKit.shared.log(event: "purchase_completed", parameters: [
    "product_id": "SKU_123",
    "price": 29.99,
    "currency": "USD"
])

// With Encodable object
struct Purchase: Encodable {
    let productId: String
    let price: Double
}
AppVitalityKit.shared.log(event: "purchase", object: Purchase(productId: "SKU", price: 9.99))

// Breadcrumb
BreadcrumbLogger.shared.log("User tapped checkout button")
```

## Configuration Options

```swift
let options = AppVitalityKit.Options(
    features: .recommended,    // or .minimal, .all
    policy: .moderate,         // .aggressive, .minimal
    flushInterval: 30,         // Upload every 30s
    maxBatchSize: 50,
    eventSampleRate: 1.0       // 1.0 = 100%
)

AppVitalityKit.shared.configure(
    apiKey: "your-api-key",
    options: options
)
```

### Feature Sets

| Set | Included |
|-----|----------|
| `.minimal` | Session, Screen View, Crashes |
| `.recommended` | + Button Taps, Breadcrumbs, Frustration |
| `.all` | + FPS, CPU, Memory, Network Monitoring |

### Sampling Policies

| Policy | Description |
|--------|-------------|
| `.minimal` | Max battery savings, 10% sampling |
| `.moderate` | Balanced (default) |
| `.aggressive` | Full capture, more battery usage |

> **Note:** Critical screens and high-risk sessions bypass sampling automatically.

## Event Types Sent

| Event Type | Description |
|------------|-------------|
| `session_start` | App foreground |
| `session_end` | App background |
| `screen_view` | ViewController appeared |
| `button_tap` | UIControl tap |
| `rage_tap` | Frustration: rapid taps |
| `dead_click` | Frustration: tap on non-interactive |
| `ghost_touch` | Frustration: tap on empty area |
| `uiHang` | Main thread blocked |
| `fpsDrop` | FPS dropped below threshold |
| `highCPU` | CPU usage spike |
| `highMemory` | Memory usage spike |
| `thermalStateCritical` | Device overheating |

## Performance Monitoring

```swift
// Automatically monitored (with .all features):
// - FPS: Drops below 45 FPS are flagged
// - CPU: Spikes above 80% are flagged
// - Memory: Usage above warning threshold
// - Thermal: Responds to thermal state changes
// - UI Hangs: Main thread blocking > 250ms
```

## Privacy

- **No IDFA** by default
- **No Personal Data** collected automatically
- **User Opt-out** supported:

```swift
// Disable tracking
AppVitalityKit.shared.stop()

// Re-enable
AppVitalityKit.shared.start()
```

- Compatible with **App Tracking Transparency (ATT)**

## Requirements

- iOS 13.0+
- Xcode 14.0+
- Swift 5.7+

## License

MIT License
