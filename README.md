# AppVitalityKit (iOS)

The official iOS SDK for [AppVitality](https://appvitality.io) - The intelligent analytics and performance monitoring platform.

## Features

- 📊 **Auto Analytics** - Automatic tracking of screens, sessions, and interactions.
- 💥 **Crash Reporting** - Catch crashes with breadcrumbs and stack traces.
- ⚡ **Performance Monitoring** - FPS, CPU, Memory, and UI Hang detection.
- 🚨 **User Risk Score** - Dynamically detects frustrated users and captures 100% of their data.
- 🎯 **Critical Path Detection** - Ensure 100% data capture on business-critical screens.
- 😤 **Frustration Detection** - Automatically detects **Rage Taps** and **Dead Clicks**.
- 🧠 **Smart Sampling** - Activity-based and device-aware (Auto-Tuning) sampling.
- 🔋 **Battery Friendly** - Automatically adjusts behavior based on battery and thermal state.

## Installation

### Swift Package Manager (Recommended)

Add the package to your Xcode project:

1. **File** → **Add Package Dependencies...**
2. Enter the repository URL:
   ```
   https://github.com/your-org/AppVitalityKit-iOS
   ```
3. Select version `1.0.0` or higher.

## Quick Start

### 1. Configure in AppDelegate

```swift
import AppVitalityKit

func application(_ application: UIApplication, didFinishLaunchingWithOptions...) -> Bool {
    
    // Initialize with your API key
    AppVitalityKit.shared.configure(apiKey: "your-api-key")
    
    return true
}
```

That's it! The SDK automatically starts tracking sessions, screens, and crashes.

## 🧠 Smart Features

### 1. User Risk Score (New)

The SDK assigns a dynamic **Risk Score** (0-100) to each user session based on frustration signals. 

- **High Risk (≥70):** The user is experiencing significant issues. The SDK **overrides sampling** and captures 100% of events.
- **Signals:** Rage Taps (+15), Dead Clicks (+10), Errors (+20), UI Hangs (+10), Crashes (+20).

No configuration required. It works automatically.

### 2. Critical Path Detection

Mark specific screens as **business-critical** (e.g., checkout, payment). Events on these screens are **always captured (100% sampling)** regardless of user activity or device state.

```swift
// Mark critical screens where you can't afford to lose data
AppVitalityKit.shared.markCriticalScreens([
    "PaymentConfirmViewController",
    "CheckoutFinalViewController",
    "SubscriptionPurchaseVC"
])
```

### 3. Frustration Detection

The SDK automatically detects when users are frustrated:

- **Rage Taps:** Rapidly tapping the same element (indicates slow UI or confusion).
- **Dead Clicks:** Tapping on non-interactive elements that *look* clickable.

These events are sent automatically and contribute to the User Risk Score.

### 4. Adaptive Sampling (Auto-Tuning)

The SDK automatically optimizes itself based on:

- **User Activity:** High interaction rate (scrolling fast) → Lower sampling (to save CPU). Low activity → Higher sampling.
- **Device Health:** 
  - **Low Battery:** Reduces upload frequency.
  - **Thermal State:** Disables heavy monitors (FPS/CPU) if device is hot.
  - **Low Power Mode:** Reduces data collection.

## Manual Event Logging

```swift
// Custom event with parameters
AppVitalityKit.shared.log(event: "purchase_completed", parameters: [
    "product_id": "SKU_123",
    "price": 29.99,
    "currency": "USD"
])
```

## Advanced Configuration

For enterprise apps with massive traffic, you can customize the default behavior:

```swift
let options = AppVitalityKit.Options(
    features: .recommended,
    policy: .moderate,
    flushInterval: 30,      // Upload every 30s
    maxBatchSize: 50,       // Batch size
    eventSampleRate: 0.1    // Sample 10% of standard events
)

AppVitalityKit.shared.configure(apiKey: "key", options: options)
```

**Note:** Critical Path and High Risk sessions will **bypass** the `eventSampleRate` limit automatically.

## Privacy

AppVitalityKit respects user privacy:
- No personal data collected by default.
- Use `AppVitalityKit.shared.stop()` to disable tracking (e.g., for user opt-out).
- Compatible with App Tracking Transparency (ATT).

## License

MIT License.
